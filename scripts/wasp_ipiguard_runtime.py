"""
AgentDojo FunctionsRuntime for WASP / VisualWebArena.

Important:
These functions DO NOT execute the browser directly.
They convert IPIGuard tool calls into WASP ID-based action strings.
The existing WASP run.py loop remains responsible for env.step(action).
"""

import sys
from pathlib import Path

ROOT = Path.home() / "WASP-Baseline-Experiments"

sys.path.insert(
    0,
    str(ROOT / "defenses/ipiguard/agentdojo/src")
)

from agentdojo.functions_runtime import FunctionsRuntime


def click(element_id: str) -> str:
    """Click an element in the current webpage.

    Args:
        element_id: Accessibility-tree element id to click.
    """
    return f"click [{element_id}]"


def type_text(
    element_id: str,
    text: str,
    press_enter: bool = True,
) -> str:
    """Type text into an element.

    Args:
        element_id: Accessibility-tree element id.
        text: Text to type.
        press_enter: Whether Enter should be pressed after typing.
    """
    if press_enter:
        return f"type [{element_id}] [{text}]"
    return f"type [{element_id}] [{text}] [0]"


def hover(element_id: str) -> str:
    """Hover over an element.

    Args:
        element_id: Accessibility-tree element id.
    """
    return f"hover [{element_id}]"


def scroll(direction: str) -> str:
    """Scroll the current page.

    Args:
        direction: Scroll direction, either up or down.
    """
    if direction not in {"up", "down"}:
        raise ValueError("direction must be 'up' or 'down'")
    return f"scroll [{direction}]"


def press(key: str) -> str:
    """Press a keyboard key or key combination.

    Args:
        key: Keyboard key or key combination.
    """
    return f"press [{key}]"


def goto(url: str) -> str:
    """Navigate the current tab to a URL.

    Args:
        url: Destination URL.
    """
    return f"goto [{url}]"


def new_tab() -> str:
    """Open a new browser tab."""
    return "new_tab"


def tab_focus(tab_index: int) -> str:
    """Switch focus to a browser tab.

    Args:
        tab_index: Zero-based browser tab index.
    """
    return f"tab_focus [{tab_index}]"


def go_back() -> str:
    """Navigate backward in browser history."""
    return "go_back"


def go_forward() -> str:
    """Navigate forward in browser history."""
    return "go_forward"


def stop(answer: str = "") -> str:
    """Finish the task and optionally provide an answer.

    Args:
        answer: Optional final answer.
    """
    return f"stop [{answer}]"


def build_wasp_runtime() -> FunctionsRuntime:
    runtime = FunctionsRuntime()

    for fn in [
        click,
        type_text,
        hover,
        scroll,
        press,
        goto,
        new_tab,
        tab_focus,
        go_back,
        go_forward,
        stop,
    ]:
        runtime.register_function(fn)

    return runtime


if __name__ == "__main__":
    runtime = build_wasp_runtime()

    print("Registered functions:")
    for name in runtime.functions:
        print(" -", name)

    print()
    print("===== execution tests =====")

    tests = [
        ("click", {"element_id": "123"}),
        ("type_text", {
            "element_id": "42",
            "text": "hello world",
        }),
        ("scroll", {"direction": "down"}),
        ("goto", {"url": "http://example.com"}),
        ("go_back", {}),
        ("stop", {"answer": "done"}),
    ]

    for name, kwargs in tests:
        result, error = runtime.run_function(
            None,
            name,
            kwargs,
        )
        print(
            name,
            "=>",
            repr(result),
            "error=",
            error,
        )
