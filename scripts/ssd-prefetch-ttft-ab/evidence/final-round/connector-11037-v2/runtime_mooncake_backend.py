# Standard
import functools
import json
import os
import threading
from dataclasses import dataclass
from typing import Any

import regex as re
import torch

# Third Party
from mooncake.store import ReplicateConfig  # type: ignore
from vllm.config import ParallelConfig
from vllm.distributed.parallel_state import get_world_group
from vllm.logger import logger
from vllm.utils.network_utils import get_ip

from vllm_ascend.distributed.kv_transfer.kv_pool.ascend_store.backend.backend import Backend

# Image rc1 tree has no backend/base.py. Values from M41 base.py.
QOS_VALUE_MIN = 0
QOS_VALUE_MAX = 4
from vllm_ascend.distributed.kv_transfer.utils.mooncake_transfer_engine import global_te
from vllm_ascend.distributed.parallel_state import get_global_rank

DEFAULT_GLOBAL_SEGMENT_SIZE = 1073741824  # 1.0 GiB
DEFAULT_LOCAL_BUFFER_SIZE = 1073741824  # 1.0 GiB
DEFAULT_TENANT_ID = "default"


@functools.lru_cache(maxsize=1)
def _mooncake_setup_supports_ssd_offload() -> bool:
    """True when installed Mooncake exposes SSD kwargs on setup() (v0.3.11+)."""
    from mooncake.store import MooncakeDistributedStore  # type: ignore

    setup = MooncakeDistributedStore.setup
    try:
        import inspect

        sig = inspect.signature(setup)
        return "enable_ssd_offload" in sig.parameters
    except (TypeError, ValueError):
        # pybind11 overloaded bindings often reject inspect.signature
        doc = setup.__doc__ or ""
        return "enable_ssd_offload" in doc


@functools.lru_cache(maxsize=1)
def _mooncake_exist_options_class() -> type | None:
    """Return ``ExistOptions`` when the installed Mooncake exposes it."""
    try:
        from mooncake.store import ExistOptions  # type: ignore

        options = ExistOptions()
        if hasattr(options, "prefetch_to_memory"):
            return ExistOptions
    except Exception:
        pass
    return None


@functools.lru_cache(maxsize=1)
def _mooncake_is_exist_supports_prefetch() -> bool:
    """True when installed Mooncake exposes ``ExistOptions`` for is_exist / batch_is_exist.

    Mooncake RFC #2213 adds ``batch_is_exist(keys, ExistOptions(prefetch_to_memory=True))``
    which triggers SSD-to-DRAM promotion for keys that only have a LOCAL_DISK replica.
    The feature was proposed after v0.3.11, so it requires a newer build.
    """
    return _mooncake_exist_options_class() is not None


def _build_exist_prefetch_options() -> Any:
    exist_options_cls = _mooncake_exist_options_class()
    if exist_options_cls is None:
        raise RuntimeError("Mooncake ExistOptions is not available")
    options = exist_options_cls()
    options.prefetch_to_memory = True
    return options


def _ssd_setup_kwargs(config: "MooncakeStoreConfig") -> dict[str, object]:
    """Keyword args for store.setup(); empty on old Mooncake or when SSD is off."""
    if not config.enable_ssd_offload:
        return {}
    if not _mooncake_setup_supports_ssd_offload():
        raise RuntimeError(
            "mooncake.json has enable_ssd_offload=true, but the installed "
            "Mooncake does not support enable_ssd_offload/ssd_offload_path in "
            "MooncakeDistributedStore.setup(). Upgrade Mooncake to v0.3.11 or "
            "later (see Mooncake ssd-offload.md Step 3A), or set "
            "enable_ssd_offload to false."
        )
    kwargs: dict[str, object] = {
        "enable_ssd_offload": config.enable_ssd_offload,
        "ssd_offload_path": config.ssd_offload_path,
    }
    # SSD prefetch throttle (memory-pressure backoff + per-key dedup).
    # ExistOptions can ship without these setup() kwargs (HEAD c86d8cca
    # setup() is positional + dict only). Probe the binding doc, not
    # ExistOptions. Omit unset knobs so Mooncake uses its defaults.
    setup_doc = ""
    try:
        from mooncake.store import MooncakeDistributedStore  # type: ignore

        setup_doc = MooncakeDistributedStore.setup.__doc__ or ""
    except Exception:
        setup_doc = ""
    if "ssd_prefetch_cooldown_sec" in setup_doc and config.ssd_prefetch_cooldown_sec is not None:
        kwargs["ssd_prefetch_cooldown_sec"] = config.ssd_prefetch_cooldown_sec
    if "ssd_prefetch_dedup_ttl_sec" in setup_doc and config.ssd_prefetch_dedup_ttl_sec is not None:
        kwargs["ssd_prefetch_dedup_ttl_sec"] = config.ssd_prefetch_dedup_ttl_sec
    return kwargs


@functools.lru_cache(maxsize=1)
def _mooncake_setup_has_config_dict() -> bool:
    """True when setup() has the config-dict overload (prefetch knobs live there)."""
    try:
        from mooncake.store import MooncakeDistributedStore  # type: ignore

        doc = MooncakeDistributedStore.setup.__doc__ or ""
        return "Supported keys:" in doc and "enable_ssd_prefetch" in doc
    except Exception:
        return False


def _stringify_setup_cfg(cfg: dict[str, object]) -> dict[str, str]:
    # pybind copies every value through py::str; TryParseBool wants true/false.
    out: dict[str, str] = {}
    for key, val in cfg.items():
        if val is True:
            out[key] = "true"
        elif val is False:
            out[key] = "false"
        else:
            out[key] = str(val)
    return out


def _validate_store_qos() -> None:
    """Validate the store QoS configured via ASCEND_GLOBAL_RESOURCE_CONFIG.

    KV pool transfers go through the Mooncake store, whose HIXL QoS comes from
    the ``store.comm_resource_config.qos`` field. The top-level
    ``comm_resource_config.qos`` belongs to other HIXL users and is not
    validated here. Only integers in [QOS_VALUE_MIN, QOS_VALUE_MAX] are
    supported; an invalid value fails fast with a clear error instead of an
    obscure failure inside the transfer engine.
    """
    config_str = os.getenv("ASCEND_GLOBAL_RESOURCE_CONFIG")
    if not config_str:
        return
    try:
        config = json.loads(config_str)
    except json.JSONDecodeError as e:
        raise ValueError(
            f"ASCEND_GLOBAL_RESOURCE_CONFIG is not valid JSON: {e}. "
            'Expected e.g. \'{"store": {"comm_resource_config": {"qos": 3}}}\'.'
        ) from e
    if not isinstance(config, dict):
        return
    store_config = config.get("store")
    if not isinstance(store_config, dict):
        return
    comm_resource_config = store_config.get("comm_resource_config")
    if not isinstance(comm_resource_config, dict) or "qos" not in comm_resource_config:
        return
    qos = comm_resource_config["qos"]
    if isinstance(qos, bool) or not isinstance(qos, int) or not (QOS_VALUE_MIN <= qos <= QOS_VALUE_MAX):
        raise ValueError(
            f"Invalid store QoS {qos!r} in ASCEND_GLOBAL_RESOURCE_CONFIG "
            f"(store.comm_resource_config.qos): QoS must be an integer in "
            f"[{QOS_VALUE_MIN}, {QOS_VALUE_MAX}]."
        )


class MooncakeBackend(Backend):
    def __init__(self, parallel_config: ParallelConfig, lazy_init: bool = False, contribute_memory: bool = True):
        self.parallel_config = parallel_config
        self.config = MooncakeStoreConfig.load_from_env()
        if self.config.protocol != "ascend":
            raise NotImplementedError(f"MooncakeBackend does not support protocol {self.config.protocol!r}.")
        _validate_store_qos()

        self.store: Any | None = None
        self.local_seg: str | None = None
        self._use_fabric_mem = os.getenv("ASCEND_ENABLE_USE_FABRIC_MEM", "0") == "1"
        # ASCEND_GLOBAL_RESOURCE_CONFIG: dual-protocol / RoCE Store path where the store
        # operates independently of the global transfer engine; setup goes through store
        # and buffers are registered via store.register_buffer() instead of global_te.
        self._use_store_independent_te = bool(os.getenv("ASCEND_GLOBAL_RESOURCE_CONFIG")) and not self._use_fabric_mem
        self._lazy_init = lazy_init and self._use_fabric_mem
        self._contribute_memory = contribute_memory
        self._store_initialized = False
        self._store_init_lock = threading.Lock()
        self._ssd_prefetch_enabled = False
        self._exist_prefetch_options: Any | None = None
        self._store_owns_te = False

        if not self._lazy_init:
            self.store = self._setup_store()
            self._store_initialized = True

    def ensure_initialized(self):
        if self._store_initialized:
            return

        with self._store_init_lock:
            if self._store_initialized:
                return

            logger.info("Initializing Mooncake store. metadata_server=%s", self.config.metadata_server)
            self.store = self._setup_store()
            self._store_initialized = True

    def _setup_store(self):
        try:
            from mooncake.store import MooncakeDistributedStore  # type: ignore
        except ImportError as e:
            raise ImportError(
                "Please install mooncake by following the instructions at "
                "https://github.com/kvcache-ai/Mooncake/blob/main/doc/en/build.md "  # noqa: E501
                "to run vLLM with MooncakeConnector."
            ) from e

        store = MooncakeDistributedStore()
        local_hostname = get_ip()
        ssd_kwargs = _ssd_setup_kwargs(self.config)
        # Each rank that contributes memory to the pool uses its own SSD
        # directory to avoid bucket file collisions. Key by the globally unique
        # rank so that DP/TP/PP/CP replicas never share a directory (dense and
        # MoE alike); only ranks that contribute memory need an offload dir.
        if ssd_kwargs and ssd_kwargs.get("ssd_offload_path") and self._contribute_memory:
            global_rank = get_global_rank(self.parallel_config)
            rank_path = os.path.join(str(ssd_kwargs["ssd_offload_path"]), f"rank_{global_rank}")
            try:
                os.makedirs(rank_path, exist_ok=True)
            except OSError as e:
                raise RuntimeError(f"Failed to create per-rank SSD offload directory: {rank_path!r} ({e})")
            ssd_kwargs["ssd_offload_path"] = rank_path
        setup_kwargs = dict(ssd_kwargs)
        if self.config.tenant_id != DEFAULT_TENANT_ID:
            setup_kwargs["tenant_id"] = self.config.tenant_id
        # HEAD store.setup() only accepts prefetch/wait knobs on the config-dict
        # overload, which does not take a shared TransferEngine. Store owns TE;
        # register_buffer must go through store, not global_te.
        if _mooncake_setup_has_config_dict():
            self._store_owns_te = True
            self.local_seg = local_hostname
            wait_ms = self.config.ssd_get_wait_ms
            if wait_ms is None and os.environ.get("MOONCAKE_SSD_GET_WAIT_MS"):
                wait_ms = int(os.environ["MOONCAKE_SSD_GET_WAIT_MS"])
            setup_cfg: dict[str, object] = {
                "local_hostname": local_hostname,
                "metadata_server": self.config.metadata_server,
                "global_segment_size": self.config.global_segment_size if self._contribute_memory else 0,
                "local_buffer_size": self.config.local_buffer_size if self._contribute_memory else 0,
                "protocol": self.config.protocol,
                "rdma_devices": self.config.device_name or "",
                "master_server_addr": self.config.master_server_address,
                "tenant_id": self.config.tenant_id,
                "enable_ssd_prefetch": bool(self.config.enable_ssd_prefetch),
            }
            if ssd_kwargs:
                setup_cfg["enable_ssd_offload"] = True
                setup_cfg["ssd_offload_path"] = ssd_kwargs["ssd_offload_path"]
            if self.config.ssd_prefetch_cooldown_sec is not None:
                setup_cfg["ssd_prefetch_cooldown_sec"] = self.config.ssd_prefetch_cooldown_sec
            if self.config.ssd_prefetch_dedup_ttl_sec is not None:
                setup_cfg["ssd_prefetch_dedup_ttl_sec"] = self.config.ssd_prefetch_dedup_ttl_sec
            if wait_ms is not None:
                setup_cfg["ssd_get_wait_ms"] = wait_ms
            cfg_str = _stringify_setup_cfg(setup_cfg)
            logger.info("Mooncake store.setup(config) ssd_get_wait_ms=%s cfg=%s", wait_ms, cfg_str)
            ret = store.setup(cfg_str)
        # ASCEND_ENABLE_USE_FABRIC_MEM: Enable unified memory address direct transmission scheme
        # and only can be used for 800 I/T A3 series.
        # Required supporting hardware versions are as follows:
        # ASCEND_GLOBAL_RESOURCE_CONFIG takes the same store-independent-TE setup path as fabric-mem.
        elif not self._use_fabric_mem and not self._use_store_independent_te:
            transfer_engine = global_te.get_transfer_engine(local_hostname, device_name=None)
            self.local_seg = local_hostname + ":" + str(transfer_engine.get_rpc_port())
            ret = store.setup(
                local_hostname=self.local_seg,
                metadata_server=self.config.metadata_server,
                global_segment_size=self.config.global_segment_size if self._contribute_memory else 0,
                local_buffer_size=self.config.local_buffer_size if self._contribute_memory else 0,
                protocol=self.config.protocol,
                rdma_devices=self.config.device_name,
                master_server_addr=self.config.master_server_address,
                engine=transfer_engine.get_engine(),
                **setup_kwargs,
            )
        else:
            self.local_seg = local_hostname
            ret = store.setup(
                local_hostname=self.local_seg,
                metadata_server=self.config.metadata_server,
                global_segment_size=self.config.global_segment_size if self._contribute_memory else 0,
                local_buffer_size=0,
                protocol=self.config.protocol,
                rdma_devices=self.config.device_name,
                master_server_addr=self.config.master_server_address,
                **setup_kwargs,
            )

        if ret != 0:
            msg = "Initialize mooncake failed."
            logger.error(
                "Initialize mooncake failed. ret=%d, metadata_server=%s. Check mooncake config and network.",
                ret,
                self.config.metadata_server,
            )
            raise RuntimeError(msg)
        if ssd_kwargs:
            logger.info(
                "Mooncake SSD offload enabled (Mode A): path=%s",
                self.config.ssd_offload_path,
            )
        logger.info("Mooncake tenant_id=%s", self.config.tenant_id)

        self._ssd_prefetch_enabled = self._resolve_ssd_prefetch()
        if self._ssd_prefetch_enabled:
            self._exist_prefetch_options = _build_exist_prefetch_options()
        return store

    def _resolve_ssd_prefetch(self) -> bool:
        """Decide whether to pass ``ExistOptions(prefetch_to_memory=True)`` on exist queries.

        Prefetch is only useful when SSD offload is active (keys can reside on
        disk) and the installed Mooncake build exposes ``ExistOptions`` on
        ``batch_is_exist`` / ``is_exist`` (RFC #2213).
        """
        if not self.config.enable_ssd_prefetch:
            return False
        if not self.config.enable_ssd_offload:
            logger.warning(
                "enable_ssd_prefetch is true but SSD offload is disabled; "
                "prefetch has no effect without SSD offload."
            )
            return False
        if not _mooncake_is_exist_supports_prefetch():
            logger.warning(
                "enable_ssd_prefetch is true, but the installed Mooncake does "
                "not support ExistOptions on batch_is_exist / is_exist "
                "(RFC #2213). Upgrade Mooncake to a version that implements "
                "this feature. Prefetch will be disabled."
            )
            return False
        logger.info("Mooncake SSD prefetch on exist enabled.")
        return True

    @classmethod
    def create_scheduler_client(cls, parallel_config: ParallelConfig):
        torch.npu.set_device(0)
        return cls(parallel_config, contribute_memory=False)

    def set_device(self):
        local_rank = get_world_group().local_rank
        device = torch.device(f"npu:{local_rank}")
        torch.npu.set_device(device)

    def register_buffer(self, ptrs: list[int], lengths: list[int]):
        if self._use_store_independent_te or self._store_owns_te:
            assert self.store is not None
            for ptr, length in zip(ptrs, lengths):
                ret = self.store.register_buffer(ptr, length)
                if ret != 0:
                    logger.error(
                        "Failed to register buffer via store: ptr=%s, length=%s, ret=%s",
                        ptr,
                        length,
                        ret,
                    )
        elif not self._use_fabric_mem:
            local_hostname = get_ip()
            global_te.get_transfer_engine(local_hostname, device_name=None)
            global_te.register_buffer(ptrs, lengths)

    def exists(self, keys: list[str]) -> list[int]:
        if self._lazy_init and not self._store_initialized:
            logger.debug(
                "MooncakeBackend.exists called before store initialization; treating %d keys as missing.",
                len(keys),
            )
            return [0] * len(keys)
        assert self.store is not None
        if self._ssd_prefetch_enabled and self._exist_prefetch_options is not None:
            return self.store.batch_is_exist(keys, self._exist_prefetch_options)
        return self.store.batch_is_exist(keys)

    def put(self, keys: list[str], addrs: list[list[int]], sizes: list[list[int]]):
        self.ensure_initialized()
        assert self.store is not None
        try:
            config = ReplicateConfig()
            if self.config.preferred_segment:
                config.preferred_segment = self.local_seg
            config.prefer_alloc_in_same_node = self.config.prefer_alloc_in_same_node
            res = self.store.batch_put_from_multi_buffers(keys, addrs, sizes, config)
            failed_codes = [int(value) for value in res if value < 0]
            failed_count = len(failed_codes)
            if failed_count:
                error_codes = sorted(set(failed_codes))
                logger.error(
                    "Failed to put %d keys out of %d. error_codes=%s. Check memory and store capacity.",
                    failed_count,
                    len(keys),
                    error_codes,
                )
                logger.debug("Failed to put key details. keys=%s, result=%s", keys, res)
                if self._lazy_init:
                    logger.warning("First DSV4(compress) request failure is expected. This is normal behavior.")
        except Exception as e:
            logger.error(
                "Failed to put %d keys out of %d. type=%s, error=%s. Check store state and memory.",
                len(keys),
                len(keys),
                type(e).__name__,
                e,
            )
            logger.debug("Failed to put key details. keys=%s", keys)
            if self._lazy_init:
                logger.warning("First DSV4(compress) request failure is expected. This is normal behavior.")

    def get(self, keys: list[str], addrs: list[list[int]], sizes: list[list[int]]):
        if self._lazy_init and not self._store_initialized:
            logger.error(
                "Failed to get %d keys out of %d. Store is not initialized; "
                "call put() first to trigger initialization.",
                len(keys),
                len(keys),
            )
            logger.debug("Failed to get key details. keys=%s", keys)
            return
        assert self.store is not None
        logger.debug(
            "MooncakeBackend.get enter keys=%d sample_keys=%s",
            len(keys),
            keys[:3],
        )
        try:
            res = self.store.batch_get_into_multi_buffers(keys, addrs, sizes)
            res_list = list(res)
            failed_codes = [int(value) for value in res_list if value < 0]
            failed_count = len(failed_codes)
            error_codes = sorted(set(failed_codes))
            if failed_count:
                logger.error(
                    "Failed to get %d keys out of %d. error_codes=%s. Check key existence and memory state.",
                    failed_count,
                    len(keys),
                    error_codes,
                )
                logger.debug("Failed to get key details. keys=%s, result=%s", keys, res_list)
            for i, value in enumerate(res_list):
                if value > 0:
                    res_list[i] = 0
            return res_list
        except Exception as e:
            logger.error(
                "Failed to get %d keys out of %d. type=%s, error=%s. Check store state and network.",
                len(keys),
                len(keys),
                type(e).__name__,
                e,
            )
            logger.debug("Failed to get key details. keys=%s", keys)
            return None


@dataclass
class MooncakeStoreConfig:
    metadata_server: str
    global_segment_size: int | str
    local_buffer_size: int
    protocol: str
    device_name: str
    master_server_address: str
    preferred_segment: bool
    prefer_alloc_in_same_node: bool
    enable_ssd_offload: bool = False
    ssd_offload_path: str = ""
    tenant_id: str = DEFAULT_TENANT_ID

    enable_ssd_prefetch: bool = False
    # None means "not set in mooncake.json"; in that case we do NOT pass the
    # value to store.setup() and let Mooncake fall back to its own defaults.
    ssd_prefetch_cooldown_sec: int | None = None
    ssd_prefetch_dedup_ttl_sec: int | None = None
    ssd_get_wait_ms: int | None = None

    def __post_init__(self) -> None:
        if not self.enable_ssd_offload:
            return
        if not self.ssd_offload_path:
            raise ValueError(
                "enable_ssd_offload is true but ssd_offload_path is empty. Set ssd_offload_path in mooncake.json."
            )
        if not os.path.isabs(self.ssd_offload_path):
            raise ValueError(f"ssd_offload_path must be an absolute path, got: {self.ssd_offload_path!r}")

    @staticmethod
    def from_file(file_path: str) -> "MooncakeStoreConfig":
        with open(file_path) as file:
            config = json.load(file)
        master_server_address = os.getenv("MOONCAKE_MASTER", None)
        global_segment_size_env = os.getenv("MOONCAKE_GLOBAL_SEGMENT_SIZE", None)
        return MooncakeStoreConfig(
            metadata_server=config.get("metadata_server"),
            global_segment_size=_parse_global_segment_size(
                global_segment_size_env
                if global_segment_size_env is not None
                else config.get("global_segment_size", DEFAULT_GLOBAL_SEGMENT_SIZE)
            ),
            local_buffer_size=_parse_global_segment_size(config.get("local_buffer_size", DEFAULT_LOCAL_BUFFER_SIZE)),
            protocol=config.get("protocol", "ascend"),
            device_name=config.get("device_name", ""),
            master_server_address=master_server_address
            if master_server_address is not None
            else config.get("master_server_address"),
            preferred_segment=config.get("preferred_segment", False),
            prefer_alloc_in_same_node=config.get("prefer_alloc_in_same_node", True),
            enable_ssd_offload=bool(config.get("enable_ssd_offload", False)),
            ssd_offload_path=config.get("ssd_offload_path", ""),
            tenant_id=_normalize_tenant_id(config.get("tenant_id", DEFAULT_TENANT_ID)),

            enable_ssd_prefetch=bool(config.get("enable_ssd_prefetch", False)),
            ssd_prefetch_cooldown_sec=(
                int(config["ssd_prefetch_cooldown_sec"])
                if config.get("ssd_prefetch_cooldown_sec") is not None
                else None
            ),
            ssd_prefetch_dedup_ttl_sec=(
                int(config["ssd_prefetch_dedup_ttl_sec"])
                if config.get("ssd_prefetch_dedup_ttl_sec") is not None
                else None
            ),
            ssd_get_wait_ms=(
                int(config["ssd_get_wait_ms"])
                if config.get("ssd_get_wait_ms") is not None
                else (int(os.environ["MOONCAKE_SSD_GET_WAIT_MS"]) if os.environ.get("MOONCAKE_SSD_GET_WAIT_MS") else None)
            ),
        )

    @staticmethod
    def load_from_env() -> "MooncakeStoreConfig":
        config_path = os.getenv("MOONCAKE_CONFIG_PATH")
        if not config_path:
            raise ValueError("The environment variable 'MOONCAKE_CONFIG_PATH' is not set.")
        return MooncakeStoreConfig.from_file(config_path)


def _normalize_tenant_id(value: Any) -> str:
    if value is None:
        return DEFAULT_TENANT_ID
    if not isinstance(value, str):
        raise TypeError(f"tenant_id must be a string or null, got {type(value).__name__}: {value!r}")
    tenant_id = value.strip()
    return tenant_id if tenant_id else DEFAULT_TENANT_ID


def _parse_global_segment_size(value) -> int:
    """
    Parse storage size strings with support for units: GB, MB, KB, B

    Args:
        value: Input value (int, str, or other convertible types)

    Returns:
        int: Size in bytes

    Raises:
        ValueError: For invalid format, missing number, or negative values
        TypeError: For unsupported input types
    """

    if isinstance(value, int):
        return value
    elif not isinstance(value, str):
        try:
            return int(value)
        except (TypeError, ValueError) as e:
            raise TypeError(f"Unsupported type for global_segment_size: {type(value)}") from e

    cleaned_input = value.strip().lower()
    if not cleaned_input:
        raise ValueError("global segment size cannot be empty.")

    UNIT_MULTIPLIERS = {
        "gb": 1024**3,  # 1 GB = 1024^3 bytes
        "mb": 1024**2,  # 1 MB = 1024^2 bytes
        "kb": 1024,  # 1 KB = 1024 bytes
        "b": 1,  # 1 B = 1 byte
    }
    pattern = r"^\s*([\d.]+)\s*(gb|mb|kb|b)?\s*$"
    match = re.match(pattern, cleaned_input)

    if not match:
        raise ValueError(f"Invalid format: '{value}'")

    number_str = match.group(1)
    unit = match.group(2) or "b"

    multiplier = UNIT_MULTIPLIERS[unit]
    return _convert_to_bytes(number_str, multiplier, value)


def _convert_to_bytes(number_str: str, multiplier: int, original_input: str) -> int:
    """
    Convert numeric string to byte count

    Args:
        number_str: Numeric portion of input
        multiplier: Unit conversion factor
        original_input: Original input string (for error messages)

    Returns:
        int: Byte count

    Raises:
        ValueError: For invalid numbers or negative results
    """
    try:
        numeric_value = float(number_str)
    except ValueError:
        raise ValueError(f"Invalid numeric value '{number_str}' in: '{original_input}'")
    # Calculate byte count
    try:
        byte_count = int(numeric_value * multiplier)
    except OverflowError:
        raise ValueError(f"Storage size too large: '{original_input}'")
    return byte_count
