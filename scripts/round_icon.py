from PIL import Image, ImageDraw

def create_rounded_icon(input_path, output_path, radius_percent=0.22):
    print(f"Rounding icon {input_path} -> {output_path}...")
    try:
        # Load High Res Icon
        img = Image.open(input_path).convert("RGBA")
        size = img.size[0] # Assume square
        
        # Create mask
        mask = Image.new("L", (size, size), 0)
        draw = ImageDraw.Draw(mask)
        
        # macOS Squircle isn't a simple rounded rect, but regular rounded rect is "Good Enough" for web display.
        # radius: 22% of size is roughly standard for iOS/macOS icon lookalikes on web.
        radius = int(size * radius_percent)
        
        draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
        
        # Apply mask
        rounded_img = Image.new("RGBA", (size, size), (0,0,0,0))
        rounded_img.paste(img, (0,0), mask=mask)
        
        rounded_img.save(output_path)
        print(f"Success! Saved rounded icon to {output_path}")

    except Exception as e:
        print(f"Error: {e}")

create_rounded_icon('assets/app_icon.png', 'assets/app_icon_rounded.png')
