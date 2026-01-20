import os
import re
import shutil
from pathlib import Path

import pytest


def _case_name_from_nodeid(nodeid: str) -> str:
    name = re.sub(r"[^\w.-]+", "_", nodeid).strip("_")
    return name or "case"


def _resolve_triton_dump_base() -> Path:
    base = os.environ.get("DUMP_BASE_DIR")
    if base:
        return Path(base)
    for name in ("DUMP_DIR", "TRITON_DUMP_DIR"):
        dump_dir_env = os.environ.get(name)
        if dump_dir_env:
            dump_dir = Path(dump_dir_env)
            return dump_dir.parent.parent
    raise RuntimeError("DUMP_BASE_DIR is not set and DUMP_DIR/TRITON_DUMP_DIR are missing")


def _resolve_dump_suffix() -> str:
    suffix = os.environ.get("TRITON_DUMP_SUFFIX")
    if suffix:
        return suffix
    for name in ("DUMP_DIR", "TRITON_DUMP_DIR"):
        value = os.environ.get(name)
        if value:
            suffix = Path(value).name
            if suffix:
                return suffix
    return "ta_unknown_bishengir_unknown"


def _ensure_empty_dir(path: Path, dump_base: Path) -> None:
    if not path.is_absolute():
        raise RuntimeError(f"DUMP_DIR must be absolute: {path}")
    if not dump_base.is_absolute():
        raise RuntimeError(f"DUMP_BASE_DIR must be absolute: {dump_base}")
    if dump_base == Path("/"):
        raise RuntimeError("DUMP_BASE_DIR cannot be '/'")

    resolved_base = dump_base.resolve()
    if resolved_base == Path("/"):
        raise RuntimeError("DUMP_BASE_DIR cannot resolve to '/'")

    resolved_path = path.resolve()
    try:
        resolved_path.relative_to(resolved_base)
    except ValueError as exc:
        raise RuntimeError(f"DUMP_DIR must be under DUMP_BASE_DIR: {resolved_path}") from exc

    # Expect base / case / ta_${ta}_bishengir_${bishengir}
    if resolved_path.parent == resolved_base:
        raise RuntimeError(f"DUMP_DIR must include case and suffix: {resolved_path}")
    if resolved_path.parent.parent != resolved_base:
        raise RuntimeError(f"DUMP_DIR must be base/case/suffix: {resolved_path}")

    if path.exists():
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    path.mkdir(parents=True, exist_ok=True)


def _append_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(content)


def _format_report_log(report) -> str:
    header = f"\n[{report.when}]\n"
    parts = [header]

    def add_section(label: str, text: str) -> None:
        if not text:
            return
        cleaned = text.rstrip("\n")
        parts.append(f"{label}\n{cleaned}\n")

    add_section("[stdout]", getattr(report, "capstdout", "") or "")
    add_section("[stderr]", getattr(report, "capstderr", "") or "")
    add_section("[log]", getattr(report, "caplog", "") or "")

    if report.failed:
        longrepr = getattr(report, "longreprtext", "") or str(getattr(report, "longrepr", ""))
        if longrepr:
            add_section("[error]", longrepr)

    return "".join(parts)


@pytest.fixture(autouse=True)
def triton_case_dump_path(request, monkeypatch):
    case_name = _case_name_from_nodeid(request.node.nodeid)
    dump_base = _resolve_triton_dump_base()
    dump_suffix = _resolve_dump_suffix()
    dump_dir = dump_base / case_name / dump_suffix
    _ensure_empty_dir(dump_dir, dump_base)
    monkeypatch.setenv("DUMP_DIR", str(dump_dir))
    monkeypatch.setenv("TRITON_DUMP_DIR", str(dump_dir))
    monkeypatch.setenv("TRITON_KERNEL_DUMP", os.environ.get("TRITON_KERNEL_DUMP", "1"))


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    case_name = _case_name_from_nodeid(item.nodeid)
    dump_base = _resolve_triton_dump_base()
    dump_suffix = _resolve_dump_suffix()
    dump_dir = dump_base / case_name / dump_suffix
    dump_dir.mkdir(parents=True, exist_ok=True)
    _append_text(dump_dir / "full.log", _format_report_log(report))


def pytest_collection_modifyitems(session, config, items):
    """
    通过 (文件路径, 行号) 来唯一标识测试函数。
    无论 parameterize 生成多少个用例，它们的定义行号都是一样的。
    """
    seen_definitions = set()
    selected_items = []
    deselected_items = []
    for item in items:
        # item.location 是一个元组：(文件路径, 行号, 测试名称)
        # 我们只取前两项作为“指纹”
        # file_path: 测试文件路径
        # line_no: 测试函数在代码中的定义行号（从0开始）
        file_path, line_no = item.location[0], item.location[1]
        
        # 组合成唯一 Key
        # 注意：对于同一个函数生成的多个参数化用例，这个 Key 是完全相同的
        definition_key = (file_path, line_no)
        if definition_key not in seen_definitions:
            seen_definitions.add(definition_key)
            selected_items.append(item)
        else:
            deselected_items.append(item)

    if deselected_items:
        config.hook.pytest_deselected(items=deselected_items)

    # 替换运行队列并同步计数
    items[:] = selected_items
    session.testscollected = len(items)
