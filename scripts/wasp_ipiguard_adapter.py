"""
WASP <-> IPIGuard action adapter.

This module exposes the VisualWebArena/WASP ID-based action space
as tool-like function definitions that can later be consumed by IPIGuard.
"""

from dataclasses import dataclass
from typing import Any


@dataclass
class WASPAction:
    name: str
    args: dict[str, Any]

    def to_action_string(self) -> str:
        if self.name == "click":
            return f"click [{self.args['element_id']}]"

        if self.name == "type":
            element_id = self.args["element_id"]
            text = self.args["text"]
            press_enter = self.args.get("press_enter", True)
            return (
                f"type [{element_id}] [{text}]"
                if press_enter
                else f"type [{element_id}] [{text}] [0]"
            )

        if self.name == "hover":
            return f"hover [{self.args['element_id']}]"

        if self.name == "scroll":
            return f"scroll [{self.args['direction']}]"

        if self.name == "press":
            return f"press [{self.args['key']}]"

        if self.name == "goto":
            return f"goto [{self.args['url']}]"

        if self.name == "new_tab":
            return "new_tab"

        if self.name == "tab_focus":
            return f"tab_focus [{self.args['tab_index']}]"

        if self.name == "go_back":
            return "go_back"

        if self.name == "go_forward":
            return "go_forward"

        if self.name == "stop":
            return f"stop [{self.args.get('answer', '')}]"

        raise ValueError(f"Unsupported WASP action: {self.name}")


WASP_TOOL_SCHEMAS = [
    {
        "name": "click",
        "description": "Click an element in the current webpage using its accessibility-tree element id.",
        "parameters": {
            "type": "object",
            "properties": {
                "element_id": {
                    "type": "string",
                    "description": "The element id shown in the current accessibility tree.",
                }
            },
            "required": ["element_id"],
        },
    },
    {
        "name": "type",
        "description": "Type text into an element identified by its accessibility-tree id.",
        "parameters": {
            "type": "object",
            "properties": {
                "element_id": {"type": "string"},
                "text": {"type": "string"},
                "press_enter": {
                    "type": "boolean",
                    "description": "Whether Enter should be pressed after typing.",
                    "default": True,
                },
            },
            "required": ["element_id", "text"],
        },
    },
    {
        "name": "hover",
        "description": "Hover over an element.",
        "parameters": {
            "type": "object",
            "properties": {
                "element_id": {"type": "string"}
            },
            "required": ["element_id"],
        },
    },
    {
        "name": "scroll",
        "description": "Scroll the current page.",
        "parameters": {
            "type": "object",
            "properties": {
                "direction": {
                    "type": "string",
                    "enum": ["up", "down"],
                }
            },
            "required": ["direction"],
        },
    },
    {
        "name": "press",
        "description": "Press a keyboard key or key combination.",
        "parameters": {
            "type": "object",
            "properties": {
                "key": {"type": "string"}
            },
            "required": ["key"],
        },
    },
    {
        "name": "goto",
        "description": "Navigate the current browser tab to a URL.",
        "parameters": {
            "type": "object",
            "properties": {
                "url": {"type": "string"}
            },
            "required": ["url"],
        },
    },
    {
        "name": "new_tab",
        "description": "Open a new browser tab.",
        "parameters": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "tab_focus",
        "description": "Switch focus to a browser tab.",
        "parameters": {
            "type": "object",
            "properties": {
                "tab_index": {"type": "integer"}
            },
            "required": ["tab_index"],
        },
    },
    {
        "name": "go_back",
        "description": "Navigate backward in browser history.",
        "parameters": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "go_forward",
        "description": "Navigate forward in browser history.",
        "parameters": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "stop",
        "description": "Finish the task and optionally return a final answer.",
        "parameters": {
            "type": "object",
            "properties": {
                "answer": {"type": "string"}
            },
        },
    },
]


def tool_call_to_wasp_action(function_name: str, args: dict[str, Any]) -> str:
    return WASPAction(function_name, args).to_action_string()


if __name__ == "__main__":
    tests = [
        ("click", {"element_id": "123"}),
        ("type", {"element_id": "42", "text": "hello world"}),
        ("type", {"element_id": "42", "text": "hello world", "press_enter": False}),
        ("scroll", {"direction": "down"}),
        ("goto", {"url": "http://example.com"}),
        ("go_back", {}),
        ("stop", {"answer": "done"}),
    ]

    for name, args in tests:
        print(name, "=>", tool_call_to_wasp_action(name, args))

    print(f"\nDefined {len(WASP_TOOL_SCHEMAS)} WASP tools.")
