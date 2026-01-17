from PIL import Image

def recover_icon(preview_path, output_path):
    print(f"Recovering icon from {preview_path}...")
    try:
        preview = Image.open(preview_path).convert("RGBA")
        # Preview Structure:
        # Left 100px: Dark Mode (White Icon)
        # Right 100px: Light Mode (Black Icon)
        # Icon Size: 44x44
        # Centered in 100x44 blocks.
        
        bg_width = 100
        icon_size = 44
        offset_x = (bg_width - icon_size) // 2
        
        # Target: The Black Icon on the Right
        # Start X = 100 + offset_x
        start_x = bg_width + offset_x
        start_y = 0 # It matches height
        
        box = (start_x, start_y, start_x + icon_size, start_y + icon_size)
        print(f"Cropping box: {box}")
        
        icon = preview.crop(box)
        icon.save(output_path)
        print(f"Success! Recovered icon to {output_path}")

    except Exception as e:
        print(f"Error: {e}")

recover_icon('/Users/leon/.gemini/antigravity/brain/105ea277-2e66-4bf7-a92c-81e84afc3582/preview_v11.png', 'assets/tray_icon.png')
