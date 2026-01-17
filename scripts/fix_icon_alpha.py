from PIL import Image

def process_icon(input_path, output_path):
    print(f"Restoring {input_path} to BLACK Template Icon at {output_path}...")
    try:
        img = Image.open(input_path).convert("RGBA")
        
        # 1. Extract Alpha Channel (Shape)
        # We trust the Shape of V4.
        r, g, b, a = img.split()
        
        # 2. Create Solid Black Image
        black = Image.new("RGB", img.size, (0, 0, 0))
        final = black.convert("RGBA")
        
        # 3. Apply Alpha
        final.putalpha(a)
        
        # 4. Resize/Padding Logic
        # V4 might be large. Resize to 44x44 Canvas with 36x36 Content.
        # Check size first
        if img.width != 44:
            # Resize content to fit in 38x38 (leaving 3px padding)
            content_size = 38
            content = final.resize((content_size, content_size), Image.Resampling.LANCZOS)
            
            # Place on 44x44 Canvas
            canvas = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
            offset = (44 - content_size) // 2
            canvas.paste(content, (offset, offset))
            final = canvas
            
        final.save(output_path)
        print(f"Success! Restored icon saved to {output_path}")

    except Exception as e:
        print(f"Error: {e}")

# Process
process_icon('assets/tray_icon_restore.png', 'assets/tray_icon_final_v5.png')
