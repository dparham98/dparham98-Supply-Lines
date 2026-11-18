"""Check the visible effect of the review's R control on both train instances."""
import argparse
from collections import Counter
import json
from pathlib import Path

from PIL import Image


def blue(pixel):
    r, g, b = pixel
    return b - r >= 34 and b - g >= 16 and g - r >= 10


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    before = Image.open(args.frames / "teams.png").convert("RGB")
    after = Image.open(args.frames / "front_recolored.png").convert("RGB")
    assert before.size == after.size == (1280, 900)
    red_to_blue = 0
    rear_delta = Counter()
    # The dividing line runs through the gap between the two parallel tracks.
    # Stay 50 px away from it and sample saturated red / blue body paint.
    old_pixels, new_pixels = before.load(), after.load()
    for i in range(1280 * 900):
        x, y = i % 1280, i // 1280
        old, new = old_pixels[x, y], new_pixels[x, y]
        distance = y - 450 + 0.312 * (x - 640)
        if distance > 50 and old[0] - max(old[1], old[2]) > 35 and blue(new):
            red_to_blue += 1
        elif distance < -50 and blue(old):
            rear_delta[max(abs(a - b) for a, b in zip(old, new))] += 1
    rear_count = sum(rear_delta.values())
    changed_rear = sum(n for delta, n in rear_delta.items() if delta > 4)
    result = {
        "test": "Two native 1280 x 900 Godot framebuffers before and after toggling only the front train from enemy red to review-player blue via R",
        "renderer": "Godot Forward+",
        "red_pixels_changed_to_blue_on_front_train": red_to_blue,
        "blue_pixels_sampled_on_rear_train": rear_count,
        "rear_pixels_with_any_channel_difference_over_4_of_255": changed_rear,
        "rear_largest_channel_difference_of_255": max(rear_delta, default=0),
        "pass": red_to_blue > 500 and rear_count > 500 and changed_rear == 0,
    }
    print(json.dumps(result, indent=2))
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if not result["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
