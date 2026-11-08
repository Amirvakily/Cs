#!/usr/bin/env python3
"""Download the CC0 assets BREACHLINE uses from Poly Haven (https://polyhaven.com).

All Poly Haven assets are CC0 (public domain). Run from the repository root:
    python3 tools/fetch_assets.py
Files already present are skipped. Writes Godot .import files so textures get
VRAM compression, mipmaps and correct normal-map handling when imported.
"""
import json
import os
import sys
import urllib.request

UA = {"User-Agent": "breachline-asset-fetch/1.0"}
API = "https://api.polyhaven.com"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

TEXTURES = [
    # desert map
    "dry_ground_rocks", "sandstone_blocks_08", "rough_plaster_brick_04", "clay_plaster",
    "red_sandstone_pavement", "weathered_planks", "container_side", "concrete_floor_worn_001",
    "brushed_concrete", "rusty_corrugated_iron",
    # night map
    "asphalt_02", "concrete_pavers_02", "brick_wall_10", "brick_4", "concrete_tile_facade",
    "floor_tiles_06", "dirty_tiles", "painted_metal_shutter", "metal_plate", "concrete_block_wall",
]
HDRIS = ["wasteland_clouds_puresky", "kloppenheim_07_puresky"]
MODELS = [
    "wooden_crate_02", "Barrel_01", "barrel_03", "concrete_road_barrier",
    "covered_car", "street_lamp_01", "metal_trash_can", "utility_box_01",
    "exterior_aircon_unit", "service_pistol", "bolt_action_rifle_7_62", "ammo_box",
    "metal_jerrycan", "cardboard_box_01", "portable_generator", "security_light",
    "hanging_industrial_lamp", "propane_tank",
]

TEX_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit={size_limit}
detect_3d/compress_to=0
"""


def get(url: str) -> bytes:
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def save(url: str, path: str) -> None:
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = get(url)
    with open(path, "wb") as f:
        f.write(data)
    print(f"  {os.path.relpath(path, ROOT)} ({len(data) // 1024} KB)")


def write_import(path: str, normal: bool, force: bool = False, size_limit: int = 0) -> None:
    imp = path + ".import"
    if os.path.exists(imp) and not force:
        with open(imp) as f:
            text = f.read()
            if "compress/mode=2" in text and f"process/size_limit={size_limit}" in text:
                return
    with open(imp, "w") as f:
        f.write(TEX_IMPORT.format(normal=1 if normal else 0, size_limit=size_limit))


def fetch_texture(name: str) -> None:
    files = json.loads(get(f"{API}/files/{name}"))
    for key, suffix in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("arm", "arm")):
        if key not in files:
            print(f"  ! {name} has no {key}")
            continue
        path = os.path.join(ROOT, "textures", name, f"{name}_{suffix}_1k.jpg")
        save(files[key]["1k"]["jpg"]["url"], path)
        # Roughness/AO detail is low-frequency: 512 px keeps the download small.
        write_import(path, suffix == "nor_gl", size_limit=512 if suffix == "arm" else 0)


def fetch_hdri(name: str) -> None:
    files = json.loads(get(f"{API}/files/{name}"))
    path = os.path.join(ROOT, "hdri", f"{name}_2k.hdr")
    save(files["hdri"]["2k"]["hdr"]["url"], path)
    write_import(path, False)


def fetch_model(name: str) -> None:
    files = json.loads(get(f"{API}/files/{name}"))
    g = files["gltf"]["1k"]["gltf"]
    base = os.path.join(ROOT, "models", name)
    save(g["url"], os.path.join(base, f"{name}_1k.gltf"))
    for rel, info in g["include"].items():
        path = os.path.join(base, rel)
        save(info["url"], path)
        if rel.endswith((".jpg", ".png")):
            # Godot only auto-detects 3D usage in the editor UI; force VRAM + mipmaps.
            # Props are small on screen: cap their textures at 512 px to keep the download small.
            write_import(path, "nor_gl" in rel, size_limit=512)


def main() -> int:
    print("Textures:")
    for t in TEXTURES:
        fetch_texture(t)
    print("HDRIs:")
    for h in HDRIS:
        fetch_hdri(h)
    print("Models:")
    for m in MODELS:
        fetch_model(m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
