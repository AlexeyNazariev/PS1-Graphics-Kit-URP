🎮 PS1 Graphics Kit for Unity URP

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Unity](https://img.shields.io/badge/Unity-2021.3%2B-blue.svg)](https://unity.com/)
[![Platform](https://img.shields.io/badge/Platform-Universal%20Render%20Pipeline-lightgrey.svg)](https://unity.com/render-pipelines/universal-render-pipeline)

A comprehensive toolset designed to recreate the authentic retro-aesthetic of 32-bit era consoles (PS1 style) within Unity's Universal Render Pipeline (URP). This kit includes custom shaders with vertex jitter, a resolution-independent pixelization system, and an advanced billboard solution.

---

<img src="PS1-Graphics-Kit.gif" width="600">

🌟 Key Features

⚡ Vertex Jitter (Affine Mapping Simulation)
The hallmark of the PS1 aesthetic is the lack of a high-precision Z-buffer and fixed coordinate snapping.
* **How it works**: The shaders use a custom `ApplyJitter` function to snap vertex positions to a virtual grid in Clip Space.
* **The Result**: Characteristic geometry "wobble" when objects or the camera move.

🖼 Perfect Pixelization
A smart post-processing shader that doesn't just stretch the image, but calculates the ideal scale based on your desired resolution.
* **Resolution Independence**: Pixels remain perfectly square regardless of your monitor's aspect ratio or resolution.
* **Customization**: Simply set your target virtual height (e.g., 240p), and the shader handles the math to keep the grid clean.

🌲 Billboard & Shadow System
A specialized script and shader combo for 2D sprites in a 3D world, solving common flat-object lighting issues.
* **Orientation Control**: Objects can face the camera while locking specific axes (like Y-axis for trees).
* **Dynamic Shadows**: Automatically projects shadows onto the ground using Raycasts, supporting both modern URP Decals and simple Quads.
* **Shadow Polish**: Features dynamic fading and scaling based on the distance from the ground.

---

📂 Project Overview

| File | Description |
| :--- | :--- |
| `PS1_ObjectShader.shader` | The primary Lit shader for 3D models. Supports shadows, jitter, and Alpha Cutoff. |
| `PS1_Billboard.shader` | Optimized Unlit shader for foliage/sprites with jitter and fog support. |
| `PS1_TerrainLit.shader` | Custom terrain implementation that synchronizes ground jitter with world objects. |
| `CustomTerrainLitPasses.hlsl` | Core HLSL library for terrain passes (Shadow, Depth, Forward). |
| `PixelizeShader.shader` | Fullscreen pixelization pass with resolution scaling. |
| `Billboard.cs` | Script for camera-facing logic and ground-projected shadow management. |

---

🛠 Setup Guide

1. Material Setup
For standard 3D models, use the `Custom/PS1_Style_Lit_Alpha_Fixed` shader. Adjust the **Jitter Resolution** to `240` (classic) or higher for a smoother effect.

2. Terrain Configuration
1. Select your **Terrain** in the scene.
2. In the **Terrain Settings** inspector, find the **Material** field.
3. Change the mode to **Custom** and assign a material using the `Custom/PS1_TerrainLit` shader.

3. Pixelization Effect
1. Create a new Material using the `Hidden/Custom/Pixelize` shader.
2. In your `URP Renderer Data` asset, add a **Full Screen Pass** renderer feature.
3. Assign your created material to this pass and set the **Virtual Height Resolution**.

4. Billboard Logic
Add the `Billboard.cs` script to any object with a sprite. 
* Set the **Ground Layer** so shadows know where to land.
* If using hills, assign a **Decal Projector** to the script for high-quality shadows that conform to the slopes.

---

💡 Pro-Tips for the Retro Look
* **Texture Settings**: Disable **Generate Mip Maps** and set **Filter Mode** to **Point (no filter)** for all textures.
* **Anti-aliasing**: Turn off MSAA and FXAA in your URP settings. Retro graphics should be sharp and "crunchy".
* **Fog**: Use the fog settings in the Billboard shader to make distant objects blend softly into the background.

---

📄 License
This project is released under the **MIT License**. You are free to use, modify, and distribute this kit as long as the original authorship is credited.

---
*Developed with love for the 32-bit aesthetic.*
