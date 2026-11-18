"""Import and render every authored review angle using the real Godot renderer."""
import argparse
from pathlib import Path
import os
import subprocess
import tempfile
import zipfile

from stage_review import PROTOTYPE, stage


def run(engine, arguments, log_name, project):
    startupinfo = None
    if os.name == "nt":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = 0
    command = [str(engine), "--path", str(project), "--log-file", str(project / log_name), *arguments]
    result = subprocess.run(command, startupinfo=startupinfo, capture_output=True, timeout=150)
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    if result.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output:
        print(output.encode("ascii", "replace").decode("ascii"))
        raise SystemExit(result.returncode or 1)
    print((project / log_name).read_text(encoding="utf-8", errors="replace")[-1500:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--directory", type=Path,
                        default=Path(tempfile.gettempdir()) / "SupplyLines_Streamliner_Art")
    parser.add_argument("--model", type=Path, default=PROTOTYPE / "export/maglev_train_cargo.glb")
    parser.add_argument("--archive", type=Path,
                        help="Test an already packaged review from a new temporary extraction.")
    parser.add_argument("--raw", type=Path, help="Raw image directory (default: sibling of the review project)")
    args = parser.parse_args()
    if args.archive:
        dest = Path(tempfile.mkdtemp(prefix="SupplyLines_Streamliner_Extracted_")).resolve()
        with zipfile.ZipFile(args.archive) as archive:
            for name in archive.namelist():
                if not (dest / name).resolve().is_relative_to(dest):
                    raise SystemExit("Invalid review archive path")
            archive.extractall(dest)
    else:
        dest = args.directory.resolve()
        stage(dest, args.model)
    raw = args.raw.resolve() if args.raw else dest.parent / (dest.name + "_frames")
    run(args.godot, ["--headless", "--import"], "import.log", dest)
    run(args.godot, ["--position", "-5000,-5000", "--resolution", "1280x900",
        "--audio-driver", "Dummy", "--", "--capture", str(raw)], "capture.log", dest)
    print("Rendered frames:", raw)


if __name__ == "__main__":
    main()
