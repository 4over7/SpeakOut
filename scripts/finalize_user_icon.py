from PIL import Image

def finalize_user_icon(input_path, output_path):
    print(f"Finalizing User Icon {input_path} -> {output_path}...")
    try:
        # Load User Icon (Likely 36x36)
        img = Image.open(input_path).convert("RGBA")
        
        # Create 44x44 Canvas (Standard macOS Menu Bar Icon Size for @2x)
        # 22pt * 2 = 44px
        target_size = 44
        canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
        
        # Center the image
        # If img is 36x36, offset is (44-36)/2 = 4
        x_offset = (target_size - img.width) // 2
        y_offset = (target_size - img.height) // 2
        
        canvas.paste(img, (x_offset, y_offset))
        
        # Ensure it is treated as a Template Icon.
        # Template icons should be Black + Alpha.
        # User image might be White or Black or Colored.
        # Color Analysis to be safe:
        # If it's pure white, we should invert it to Black (Standard Template Color).
        # MacOS usually uses Black for Template.
        # Let's check center pixel color component.
        
        center_pixel = img.getpixel((img.width//2, img.height//2))
        # If R,G,B are high (>200), it's White.
        if center_pixel[0] > 200 and center_pixel[3] > 50:
            print("Detected White Icon. Converting to Black Template...")
            # Use Alpha channel as mask for Black
            r,g,b,a = canvas.split()
            black = Image.new("RGB", canvas.size, (0,0,0))
            black_template = black.convert("RGBA")
            black_template.putalpha(a)
            black_template.save(output_path)
        else:
            print("Detected Dark/Black Icon. Saving as is...")
            canvas.save(output_path)
            
        print(f"Success! Finalized Icon saved to {output_path}")

    except Exception as e:
        print(f"Error: {e}")

finalize_user_icon('temp_assets/MenuBarIcon.imageset/MenuBarIcon@2x.png', 'assets/tray_icon_v11.png')
