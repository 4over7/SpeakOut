from PIL import Image, ImageOps

def create_preview(icon_path, output_path):
    print(f"Generating preview for {icon_path}...")
    try:
        # Load Icon (It is Black on Transparent)
        icon = Image.open(icon_path).convert("RGBA")
        
        # Simulate macOS Template Rendering in Dark Mode:
        # The system takes the alpha/shape and fills it with White.
        r, g, b, a = icon.split()
        
        # Create a Solid White image
        white_fill = Image.new("RGB", icon.size, (255, 255, 255))
        # Apply the original Alpha as mask
        white_icon = white_fill.convert("RGBA")
        white_icon.putalpha(a)
        
        # Create Background (Dark Grey macOS Menu Bar style)
        # Size: 100x44 (Icon is 44x44)
        bg_width = 100
        bg_height = 44
        # macOS Dark Menu Bar is roughly #1E1E1E to #333333 depending on wallpaper
        bg = Image.new("RGBA", (bg_width, bg_height), (40, 40, 40, 255)) 
        
        # Center icon
        offset_x = (bg_width - icon.width) // 2
        offset_y = (bg_height - icon.height) // 2
        
        bg.paste(white_icon, (offset_x, offset_y), white_icon)
        
        # Create a "Light Mode" version too, side by side
        # Light Menu Bar is roughly #E5E5E5
        bg_light = Image.new("RGBA", (bg_width, bg_height), (229, 229, 229, 255))
        # Icon stays Black (Original)
        bg_light.paste(icon, (offset_x, offset_y), icon)
        
        # Combine them
        final_w = bg_width * 2
        final_h = bg_height
        combined = Image.new("RGBA", (final_w, final_h))
        combined.paste(bg, (0, 0))
        combined.paste(bg_light, (bg_width, 0))
        
        combined.save(output_path)
        print(f"Preview saved to {output_path}")
        
    except Exception as e:
        print(f"Error: {e}")

create_preview('assets/tray_icon_v11.png', 'assets/preview_v11.png')
