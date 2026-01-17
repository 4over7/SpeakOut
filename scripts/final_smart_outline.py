from PIL import Image, ImageFilter, ImageChops, ImageDraw
import collections

def color_distance(c1, c2):
    return sum(abs(a - b) for a, b in zip(c1, c2))

def generate_v9(input_path, output_path):
    print(f"Generating V9 (Smart Selection + Sharp Outline) from {input_path}...")
    try:
        img = Image.open(input_path).convert("RGBA")
        
        # 1. Upscale for High Fidelity (400x400)
        work_size = 400
        # Use a safe margin to avoid edge artifacts
        # Paste 360x360 image into 400x400 canvas
        img_resized = img.resize((360, 360), Image.Resampling.LANCZOS)
        padded_img = Image.new("RGBA", (work_size, work_size), (0,0,0,0))
        offset = (work_size - 360) // 2
        padded_img.paste(img_resized, (offset, offset))
        
        pixels = padded_img.load()
        width, height = padded_img.size
        
        # 2. Smart Selection (Isolate Bubble)
        # Find Center Color (Teal)
        center = (width // 2, height // 2)
        target_color = pixels[center[0], center[1]]
        
        body_mask = Image.new("L", (width, height), 0)
        body_pixels = body_mask.load()
        
        # BFS Flood Fill for Body
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
                        # If color matches Teal, it's Body. 
                        # Background (White) and Squircle Edges won't match.
                        if dist < tolerance:
                            body_pixels[nx, ny] = 255
                            seen.add((nx, ny))
                            queue.append((nx, ny))
                            
        # 3. Waveform Extraction (Holes inside Body)
        # In the Body Mask, the waveform is 0 (Black holes).
        # We need a separate mask for the Waveform to thicken it nicely.
        
        # Strategy: 
        # The 'body_mask' currently has 0 for Background AND Waveform.
        # We need to distinguish them.
        # Flood Fill (0,0) on body_mask to identify "True Background".
        bg_mask = body_mask.copy()
        ImageDraw.floodfill(bg_mask, (0, 0), 128, thresh=10)
        # Now: 128=Background, 255=Body, 0=Waveform
        
        waveform_mask = Image.new("L", (width, height), 0)
        wave_pixels = waveform_mask.load()
        bg_pixels_access = bg_mask.load()
        
        for y in range(height):
            for x in range(width):
                if bg_pixels_access[x,y] == 0: # It's a hole!
                    wave_pixels[x,y] = 255
                    
        # 4. Generate Outlines (Edge Detection)
        
        # A. Body Outline
        # Filter: FIND_EDGES
        body_edges = body_mask.filter(ImageFilter.FIND_EDGES)
        # Thicken: MaxFilter (13px for approx 1.5px stroke at 44px)
        thick_body = body_edges.filter(ImageFilter.MaxFilter(13))
        
        # B. Waveform Outline
        # Filter: FIND_EDGES
        wave_edges = waveform_mask.filter(ImageFilter.FIND_EDGES)
        # Thicken: Slightly thinner? Or same? Let's match (11px)
        thick_wave = wave_edges.filter(ImageFilter.MaxFilter(11))
        
        # 5. Combine
        # Union of Body Outline and Waveform Outline
        final_mask = ImageChops.add(thick_body, thick_wave)
        
        # 6. Export
        black = Image.new("RGB", (width, height), (0, 0, 0))
        final = black.convert("RGBA")
        final.putalpha(final_mask)
        
        # Resize to 44x44
        # Content Size 36 to have padding
        content_size = 36
        content = final.resize((content_size, content_size), Image.Resampling.LANCZOS)
        
        canvas = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
        offset = (44 - content_size) // 2
        canvas.paste(content, (offset, offset))
        
        # Force Clean Edges
        pixels = canvas.load()
        for x in range(44):
            pixels[x, 0] = (0,0,0,0)
            pixels[x, 43] = (0,0,0,0)
        for y in range(44):
            pixels[0, y] = (0,0,0,0)
            pixels[43, y] = (0,0,0,0)
            
        canvas.save(output_path)
        print(f"Success! V9 Icon saved to {output_path}")

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

generate_v9('assets/app_icon.png', 'assets/tray_icon_v9.png')
