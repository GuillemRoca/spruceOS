"""Print a script's message in the UI language.

Usage: translate_text.py <Language> <text>

For scripts that draw text without PyUI (the legacy display() helper); text
sent to PyUI is translated by PyUI itself. Looks the text up in the language
file's shellMessages section and prints it unchanged when there is no match.
"""
import os
import sys

from menus.language.language import Language


def main():
    if len(sys.argv) < 3:
        return
    language, text = sys.argv[1], sys.argv[2]
    lang_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lang", language + ".json")
    if os.path.isfile(lang_file):
        Language._read_from_file(lang_file)
    # Scripts write a two-character \n for a line break; keys use real newlines.
    escaped = "\\n" in text
    result = Language.shell_message(text.replace("\\n", "\n"))
    sys.stdout.write(result.replace("\n", "\\n") if escaped else result)


if __name__ == "__main__":
    main()
