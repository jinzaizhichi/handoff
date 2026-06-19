"""handoff tail command."""

from ..config import Config


def cmd_tail(argv: list[str], config: Config):
    """handoff tail [<run-id|seq>]"""
    from .list import cmd_list

    cmd_list([*argv, "--follow"], config)
