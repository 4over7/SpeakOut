from PIL import Image, ImageFilter, ImageChops, ImageDraw
import collections

def color_distance(c1, c2):
    return sum(abs(a - b) for a, b in zip(c1, c2))

def smart_extract(input_path, output_path):
    print(f"Smart Extracting OUTLINE Icon from {input_path}...")
    try:
        # Load High Res
        img = Image.open(input_path).convert("RGBA")
        work_size = 200
        img = img.resize((work_size, work_size), Image.Resampling.LANCZOS)
        
        pixels = img.load()
        width, height = img.size
        
        # 1. Identify Masks
        # Target: Teal Body
        center = (width // 2, height // 2)
        target_color = pixels[center[0], center[1]]
        
        body_mask = Image.new("L", (width, height), 0)
        body_pixels = body_mask.load()
        
        # BFS for Body
        queue = collections.deque([center])
        seen = {center}
        body_pixels[center[0], center[1]] = 255
        tolerance = 60 
        
        while queue:
            x, y = queue.popleft()
            for dx, dy in [(-1,0), (1,0), (0,-1), (0,1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    if (nx, ny) not in seen:
                        current_color = pixels[nx, ny]
                        dist = color_distance(current_color[:3], target_color[:3])
                        
                        # Check equality/similarity to Teal
                        if dist < tolerance:
                            body_pixels[nx, ny] = 255
                            seen.add((nx, ny))
                            queue.append((nx, ny))
                            
        # 2. Identify Waveform (Inner Whites)
        # Strategy: Everything that is NOT Body and NOT connected to Edge Background.
        # Flood fill background from (0,0)
        bg_mask = Image.new("L", (width, height), 0)
        bg_pixels = bg_mask.load()
        
        # Init with inverted Body (Body is 0 in this view)
        for y in range(height):
            for x in range(width):
                if body_pixels[x,y] == 0:
                    bg_pixels[x,y] = 255 # Potential BG or Waveform
                else:
                    bg_pixels[x,y] = 0 # Body
                    
        # Flood Fill Background
        ImageDraw.floodfill(bg_mask, (0, 0), 128, thresh=10)
        
        # Now:
        # 128 = Real Background
        # 255 = Waveform (White holes inside Body)
        # 0 = Body
        
        waveform_mask = Image.new("L", (width, height), 0)
        wave_pixels = waveform_mask.load()
        bg_pixels_access = bg_mask.load()
        
        for y in range(height):
            for x in range(width):
                if bg_pixels_access[x,y] == 255:
                    wave_pixels[x,y] = 255
                    
        # 3. Create Outline from Body
        # Thickness logic: 200px -> 12px stroke (roughly 2.5px @ 44px)
        stroke_thickness = 15
        eroded_body = body_mask.filter(ImageFilter.MinFilter(stroke_thickness))
        
        # Outline = Body - Eroded
        outline_mask = ImageChops.difference(body_mask, eroded_body)
        
        # 4. Combine: Outline OR Waveform
        final_mask = ImageChops.add(outline_mask, waveform_mask)
        
        # 5. Create Final Black Template
        black = Image.new("RGB", (width, height), (0, 0, 0))
        final = black.convert("RGBA")
        final.putalpha(final_mask)
        
        # 6. Resize output
        content_size = 38
        content = final.resize((content_size, content_size), Image.Resampling.LANCZOS)
        
        canvas = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
        offset = (44 - content_size) // 2
        canvas.paste(content, (offset, offset))
        
        canvas.save(output_path)
        print(f"Success! Smart Outline saved to {output_path}")

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

smart_extract('assets/app_icon.png', 'assets/tray_icon_smart_outline.png')
