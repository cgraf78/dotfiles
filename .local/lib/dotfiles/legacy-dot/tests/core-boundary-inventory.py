#!/usr/bin/env python3
"""Inventory dependencies that cross the embedded dot-core boundary.

The standalone-dot extraction moves the convergence engine without moving
client shell, launcher, merge-hook, or doctor policy with it.  This scanner
turns today's implicit coupling into three reviewable ledgers:

* runtime files that directly source or link an embedded ``lib/dot/core`` module;
* tests whose sources or fixtures still name an embedded module; and
* functions or global variables supplied by one embedded core file and used by
  a base merge-hook or doctor module in another file.

The runtime scan parses source commands and expands statically visible path
assignments, while the test scan intentionally includes fixture and assertion
text because those paths must migrate too.

The symbol scan uses shfmt's Bash syntax tree.  A text-token scan would mistake
comments, diagnostic strings, and locally defined helpers for cross-boundary
dependencies, making the ledger both noisy and easy to distrust.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

CORE_ROOT = ".local/lib/dotfiles/legacy-dot/core/"
TEST_ROOT = ".local/lib/dotfiles/legacy-dot/tests/"
CLIENT_TEST_ROOT = ".local/lib/dotfiles/tests/"
HOOK_CONFIG_ROOT = ".config/dot/merge-hooks.d/"

IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
CORE_PATH_RE = re.compile(
    r"(?:\.local/lib/dotfiles/|(?:^|/)legacy-dot/)core/"
    r"(?P<module>[A-Za-z0-9_./${}-]+\.sh)"
)


@dataclass(frozen=True)
class ShellMetadata:
    functions: frozenset[str]
    global_variables: frozenset[str]
    assigned_variables: frozenset[tuple[str, str | None, int]]
    calls: frozenset[tuple[str, str | None]]
    variable_references: frozenset[tuple[str, str | None, int | None]]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("sources", "symbols", "tests"))
    parser.add_argument("root", type=Path)
    parser.add_argument("tracked", type=Path)
    return parser.parse_args()


def tracked_paths(path: Path) -> list[str]:
    return [line for line in path.read_text().splitlines() if line]


def is_shell_file(path: Path, text: str) -> bool:
    if path.suffix in {".sh", ".bash", ".zsh"}:
        return True
    if path.name in {".bashrc", ".zprofile", ".zshenv", ".zshrc"}:
        return True
    first_line = text.splitlines()[0] if text.splitlines() else ""
    if not first_line.startswith("#!"):
        return False
    return re.search(r"(?:^|[/\s])(bash|sh|zsh)(?:\s|$)", first_line[2:]) is not None


def modules_in_text(text: str) -> set[str]:
    return {match.group("module") for match in CORE_PATH_RE.finditer(text)}


def combine_word_parts(parts: Iterable[set[str]]) -> set[str]:
    values = {""}
    for part_values in parts:
        values = {prefix + suffix for prefix in values for suffix in part_values}
    return values


def word_values(
    word: Any,
    assignments: dict[str, list[Any]],
    resolving: frozenset[str] = frozenset(),
) -> set[str]:
    """Render statically visible word variants without executing shell code."""

    if not isinstance(word, dict):
        return {""}
    node_type = word.get("Type")
    if node_type == "Lit":
        return {word.get("Value", "")}
    if node_type == "SglQuoted":
        return {word.get("Value", "")}
    if node_type in {"Word", "DblQuoted"} or "Parts" in word:
        return combine_word_parts(
            word_values(part, assignments, resolving) for part in word.get("Parts") or []
        )
    if node_type != "ParamExp":
        # Command substitutions and arithmetic are runtime values.  Returning
        # an empty fragment still lets a literal core suffix remain visible.
        return {""}

    name = word.get("Param", {}).get("Value", "")
    values: set[str] = set()
    if name and name not in resolving:
        for assignment in assignments.get(name, []):
            values.update(word_values(assignment, assignments, resolving | frozenset({name})))
    if not values:
        values.add(f"${{{name}}}" if name else "")

    # A default/alternate expansion may contain the only visible core path.
    expansion = word.get("Exp", {}).get("Word")
    if expansion:
        values.update(word_values(expansion, assignments, resolving))
    return values


def assignment_words(tree: dict[str, Any]) -> dict[str | None, dict[str, list[Any]]]:
    assignments: dict[str | None, dict[str, list[Any]]] = {}
    for node, scope in walk(tree):
        for assignment in node.get("Assigns") or []:
            name = assignment.get("Name", {}).get("Value")
            value = assignment.get("Value")
            if name and value:
                assignments.setdefault(scope, {}).setdefault(name, []).append(value)
        if node.get("Type") != "DeclClause":
            continue
        for assignment in node.get("Args") or []:
            name = assignment.get("Name", {}).get("Value")
            value = assignment.get("Value")
            if name and value:
                assignments.setdefault(scope, {}).setdefault(name, []).append(value)
    return assignments


def visible_assignments(
    assignments: dict[str | None, dict[str, list[Any]]], scope: str | None
) -> dict[str, list[Any]]:
    visible = dict(assignments.get(None, {}))
    if scope is not None:
        # A function-local value shadows a same-named top-level value. Values
        # from unrelated functions are never candidates for this source site.
        visible.update(assignments.get(scope, {}))
    return visible


def sourced_modules(path: Path) -> set[str]:
    tree = shell_ast(path, allow_zsh=True)
    assignments = assignment_words(tree)
    modules: set[str] = set()
    for node, scope in walk(tree):
        if node.get("Type") != "CallExpr":
            continue
        arguments = node.get("Args") or []
        if len(arguments) < 2 or literal_word(arguments[0]) not in {".", "source"}:
            continue
        for value in word_values(arguments[1], visible_assignments(assignments, scope)):
            modules.update(modules_in_text(value))
    return modules


def source_inventory(root: Path, tracked: Iterable[str]) -> None:
    for relative in tracked:
        # Core owns its internal imports.  Tests use a separate, deliberately
        # broader ledger because fixture copies and path assertions must move
        # even when they are not literal source commands.
        if relative.startswith((CORE_ROOT, TEST_ROOT, CLIENT_TEST_ROOT)):
            continue

        path = root / relative
        if path.is_symlink():
            modules = modules_in_text(str(path.readlink()))
        elif not path.is_file():
            continue
        else:
            text = path.read_text(errors="replace")
            if not is_shell_file(path, text):
                continue
            # Avoid parsing unrelated mixed Bash/Zsh fragments.  A core source
            # assembled from variables must still spell both ownership path
            # components somewhere in the file to be statically attributable.
            if "lib/dot" not in text or "core" not in text:
                continue
            modules = sourced_modules(path)

        for module in sorted(modules):
            print("\t".join((relative, module, f"{CORE_ROOT}{module}")))


def test_inventory(root: Path, tracked: Iterable[str]) -> None:
    for relative in tracked:
        if not relative.startswith(TEST_ROOT):
            continue
        if relative == f"{TEST_ROOT}core-boundary-inventory.py" or relative.startswith(
            f"{TEST_ROOT}fixtures/embedded-core-"
        ):
            continue

        path = root / relative
        if path.is_symlink():
            modules = modules_in_text(str(path.readlink()))
        elif path.is_file():
            # Test comments, fixture heredocs, copies, and direct sources all
            # carry old-path migration work, so unlike the runtime scan this
            # inventory intentionally records every literal module reference.
            modules = modules_in_text(path.read_text(errors="replace"))
        else:
            continue

        for module in sorted(modules):
            print("\t".join((relative, module, f"{CORE_ROOT}{module}")))


def parse_shell_ast(source: bytes, label: str, *, allow_zsh: bool = False) -> dict[str, Any]:
    failures = []
    for dialect in ("bash", "zsh") if allow_zsh else ("bash",):
        result = subprocess.run(
            ("shfmt", "-ln", dialect, "--to-json"),
            input=source,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        failures.append(result.stderr.decode(errors="replace").strip())
    raise RuntimeError(f"shfmt could not parse {label}: {'; '.join(failures)}")


def shell_ast(path: Path, *, allow_zsh: bool = False) -> dict[str, Any]:
    return parse_shell_ast(path.read_bytes(), str(path), allow_zsh=allow_zsh)


def walk(value: Any, scope: str | None = None) -> Iterator[tuple[dict[str, Any], str | None]]:
    if isinstance(value, dict):
        yield value, scope
        child_scope = scope
        if value.get("Type") == "FuncDecl":
            name = value.get("Name", {}).get("Value", "function")
            offset = value.get("Pos", {}).get("Offset", 0)
            child_scope = f"{name}@{offset}"
        for child in value.values():
            yield from walk(child, child_scope)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child, scope)


def literal_word(word: Any) -> str | None:
    if not isinstance(word, dict):
        return None
    parts = word.get("Parts") or []
    if len(parts) != 1 or parts[0].get("Type") != "Lit":
        return None
    return parts[0].get("Value")


def declaration_argument(argument: Any) -> str | None:
    if not isinstance(argument, dict):
        return None
    if value := literal_word(argument.get("Value")):
        return value
    if argument.get("Naked"):
        return argument.get("Name", {}).get("Value")
    return None


def declared_functions(arguments: list[Any]) -> Iterator[str]:
    """Return literal names queried by ``declare/typeset -F``."""

    saw_function_flag = False
    for argument in arguments:
        value = declaration_argument(argument)
        if not value:
            continue
        if value.startswith("-"):
            saw_function_flag = "F" in value[1:] or saw_function_flag
            continue
        if saw_function_flag and IDENTIFIER_RE.fullmatch(value):
            yield value


def arithmetic_identifiers(value: Any) -> Iterator[str]:
    for node, _ in walk(value):
        if node.get("Type") != "Lit":
            continue
        identifier = node.get("Value", "")
        if IDENTIFIER_RE.fullmatch(identifier):
            yield identifier


def token_at(source: bytes, position: Any) -> str:
    if not isinstance(position, dict):
        return ""
    offset = position.get("Offset")
    if not isinstance(offset, int):
        return ""
    match = re.match(rb"\S+", source[offset:])
    return match.group().decode(errors="replace") if match else ""


def node_offset(node: Any, field: str = "Pos") -> int | None:
    if not isinstance(node, dict):
        return None
    offset = node.get(field, {}).get("Offset")
    return offset if isinstance(offset, int) else None


def command_function_references(command: str, arguments: list[Any]) -> set[str]:
    values = [literal_word(argument) for argument in arguments]
    options = {value for value in values if value and value.startswith("-")}
    operands = [
        value
        for value in values
        if value and not value.startswith("-") and IDENTIFIER_RE.fullmatch(value)
    ]
    if command == "unset":
        return set(operands) if any("f" in option[1:] for option in options) else set()
    if command == "type":
        if any(option in {"-p", "-P"} for option in options):
            return set()
        return set(operands)
    if command == "command":
        if any(option in {"-v", "-V"} for option in options):
            return set(operands)
        # `command NAME` deliberately bypasses a shell function named NAME.
        return set()
    return set()


def unset_variable_references(arguments: list[Any]) -> set[str]:
    values = [literal_word(argument) for argument in arguments]
    if any(value and value.startswith("-") and "f" in value[1:] for value in values):
        return set()
    return {
        value
        for value in values
        if value and not value.startswith("-") and IDENTIFIER_RE.fullmatch(value)
    }


_INHERIT_SCOPE = object()
_INHERIT_OFFSET = object()


def collect_reference_events(
    tree: dict[str, Any],
    source: bytes,
    assignments: dict[str | None, dict[str, list[Any]]],
    calls: set[tuple[str, str | None]],
    variable_references: set[tuple[str, str | None, int | None]],
    *,
    fixed_scope: str | None | object = _INHERIT_SCOPE,
    fixed_offset: int | None | object = _INHERIT_OFFSET,
    parse_traps: bool = True,
) -> None:
    for node, parsed_scope in walk(tree):
        scope = parsed_scope if fixed_scope is _INHERIT_SCOPE else fixed_scope
        offset = node_offset(node) if fixed_offset is _INHERIT_OFFSET else fixed_offset

        if node.get("Type") == "DeclClause":
            for name in declared_functions(node.get("Args") or []):
                calls.add((name, scope))

        if node.get("Type") == "CallExpr":
            arguments = node.get("Args") or []
            if arguments and (name := literal_word(arguments[0])):
                calls.add((name, scope))
                if name in {"declare", "typeset"}:
                    calls.update(
                        (declared, scope) for declared in declared_functions(arguments[1:])
                    )
                elif name == "trap" and len(arguments) > 1 and parse_traps:
                    visible = visible_assignments(assignments, parsed_scope)
                    for action in word_values(arguments[1], visible):
                        if not action or action == "-":
                            continue
                        action_source = action.encode()
                        action_tree = parse_shell_ast(action_source, "trap action")
                        collect_reference_events(
                            action_tree,
                            action_source,
                            assignment_words(action_tree),
                            calls,
                            variable_references,
                            fixed_scope=scope,
                            fixed_offset=offset,
                            parse_traps=False,
                        )
                elif name in {"command", "type", "unset"}:
                    calls.update(
                        (referenced, scope)
                        for referenced in command_function_references(name, arguments[1:])
                    )
                    if name == "unset":
                        variable_references.update(
                            (referenced, scope, offset)
                            for referenced in unset_variable_references(arguments[1:])
                        )
                elif name in {"test", "["}:
                    values = [literal_word(argument) for argument in arguments[1:]]
                    for index, value in enumerate(values[:-1]):
                        candidate = values[index + 1]
                        if value == "-v" and candidate and IDENTIFIER_RE.fullmatch(candidate):
                            variable_references.add((candidate, scope, offset))

        if node.get("Type") == "ParamExp":
            name = node.get("Param", {}).get("Value", "")
            if IDENTIFIER_RE.fullmatch(name):
                variable_references.add((name, scope, offset))

        if node.get("Type") in {"ArithmCmd", "ArithmExp"}:
            variable_references.update(
                (name, scope, offset) for name in arithmetic_identifiers(node.get("X"))
            )

        if node.get("Type") == "UnaryTest" and token_at(source, node.get("OpPos")) == "-v":
            name = literal_word(node.get("X"))
            if name and IDENTIFIER_RE.fullmatch(name):
                variable_references.add((name, scope, offset))


def shell_metadata(path: Path) -> ShellMetadata:
    functions: set[str] = set()
    global_variables: set[str] = set()
    assigned_variables: set[tuple[str, str | None, int]] = set()
    calls: set[tuple[str, str | None]] = set()
    variable_references: set[tuple[str, str | None, int | None]] = set()

    source = path.read_bytes()
    tree = shell_ast(path)
    for node, scope in walk(tree):
        if node.get("Type") == "FuncDecl":
            name = node.get("Name", {}).get("Value")
            if name:
                functions.add(name)

        for assignment in node.get("Assigns") or []:
            name = assignment.get("Name", {}).get("Value")
            if not name:
                continue
            assigned_variables.add((name, scope, node_offset(assignment, "End") or 0))
            if scope is None:
                global_variables.add(name)

        if node.get("Type") == "DeclClause":
            declaration_arguments = node.get("Args") or []
            declared = set(declared_functions(declaration_arguments))
            if not declared:
                for declaration in declaration_arguments:
                    name = declaration.get("Name", {}).get("Value")
                    if not name:
                        continue
                    assigned_variables.add((name, scope, node_offset(declaration, "End") or 0))
                    if scope is None:
                        global_variables.add(name)

    collect_reference_events(
        tree,
        source,
        assignment_words(tree),
        calls,
        variable_references,
    )

    return ShellMetadata(
        functions=frozenset(functions),
        global_variables=frozenset(global_variables),
        assigned_variables=frozenset(assigned_variables),
        calls=frozenset(calls),
        variable_references=frozenset(variable_references),
    )


def is_symbol_consumer(relative: str) -> bool:
    if not relative.endswith(".sh"):
        return False
    return relative.startswith(
        (
            f"{CORE_ROOT}doctor/",
            f"{CORE_ROOT}merge-hooks/",
            HOOK_CONFIG_ROOT,
        )
    )


def variable_reference_is_owned(
    name: str,
    scope: str | None,
    offset: int | None,
    assignments: frozenset[tuple[str, str | None, int]],
) -> bool:
    for assigned_name, assigned_scope, assignment_end in assignments:
        if assigned_name != name:
            continue
        if assigned_scope is None:
            # Hooks and doctor modules finish top-level initialization before
            # the framework calls a function defined in the file.
            if scope is not None:
                return True
            if offset is not None and assignment_end <= offset:
                return True
        elif assigned_scope == scope and offset is not None and assignment_end <= offset:
            return True
    return False


def symbol_inventory(root: Path, tracked: Iterable[str]) -> None:
    engine_files = sorted(
        relative
        for relative in tracked
        if relative.startswith(CORE_ROOT) and relative.endswith(".sh")
    )
    consumers = sorted(relative for relative in tracked if is_symbol_consumer(relative))

    metadata = {
        relative: shell_metadata(root / relative)
        for relative in sorted(set(engine_files + consumers))
    }

    function_owners: dict[str, set[str]] = {}
    variable_owners: dict[str, set[str]] = {}
    for relative in engine_files:
        for name in metadata[relative].functions:
            function_owners.setdefault(name, set()).add(relative)
        for name in metadata[relative].global_variables:
            variable_owners.setdefault(name, set()).add(relative)

    for relative in consumers:
        consumer = metadata[relative]

        called_names = {name for name, _ in consumer.calls}
        for name in sorted(called_names & function_owners.keys()):
            owners = function_owners[name] - {relative}
            if name in consumer.functions or not owners:
                continue
            print("\t".join(("function", relative, name, ",".join(sorted(owners)))))

        referenced_names = {name for name, _, _ in consumer.variable_references}
        for name in sorted(referenced_names & variable_owners.keys()):
            owners = variable_owners[name] - {relative}
            references = {
                (scope, offset)
                for referenced, scope, offset in consumer.variable_references
                if referenced == name
            }
            if not owners or all(
                variable_reference_is_owned(name, scope, offset, consumer.assigned_variables)
                for scope, offset in references
            ):
                continue
            print("\t".join(("variable", relative, name, ",".join(sorted(owners)))))


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    tracked = tracked_paths(args.tracked)

    try:
        if args.kind == "sources":
            source_inventory(root, tracked)
        elif args.kind == "tests":
            test_inventory(root, tracked)
        else:
            symbol_inventory(root, tracked)
    except (
        OSError,
        RuntimeError,
        subprocess.SubprocessError,
        json.JSONDecodeError,
    ) as error:
        print(f"core-boundary-inventory: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
