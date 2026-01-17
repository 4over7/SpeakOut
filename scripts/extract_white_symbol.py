from PIL import Image, ImageFilter
import sys

def extract_white_symbol(input_path, output_path):
    print(f"Extracting White Symbol from {input_path}...")
    try:
        img = Image.open(input_path).convert("RGBA")
        # Upscale for smooth processing
        work_size = 400
        img = img.resize((work_size, work_size), Image.Resampling.LANCZOS)
        
        width, height = img.size
        
        # Create Mask from Luminance (White Pixels)
        # Luminance > 150 = Symbol
        r,g,b,a = img.split()
        
        # Calculate Luminance manually since 'L' mode loses Alpha info context
        # But we can just use pixel access or point function
        # L = 0.299R + 0.587G + 0.114B, or just average
        
        # Let's use a new image for the mask
        symbol_mask = Image.new("L", (width, height), 0)
        pixels = img.load()
        mask_pixels = symbol_mask.load()
        
        for y in range(height):
            for x in range(width):
                r,g,b,a = pixels[x,y]
                lum = (r+g+b)//3
                if lum > 180: # Threshold for White
                    mask_pixels[x,y] = 255
                else:
                    mask_pixels[x,y] = 0
                    
        # Now we have the raw symbol shape.
        # It might be thin (since it's an app icon detail).
        # And we want an OUTLINE style or FILLED style?
        # The User liked "V4 Shape" which was "Speech Bubble with Tail".
        # If the white symbol IS the filled bubble, then 'symbol_mask' is a filled bubble.
        # If the white symbol IS an outline bubble, then 'symbol_mask' is an outline.
        
        # Let's inspect the mask properties by checking if center is filled.
        # But for now, let's assume we want to "Template-ize" this exactly.
        # User wants "Outline Style" (Black/White lines, transparent fill).
        # If the original white symbol IS filled white... 
        # Then acts like a filled block.
        # If so, we need to EdgeDetect IT.
        
        # Let's FIND EDGES of the symbol to be safe and ensure "Hollow" look.
        # But if the symbol is *already* an outline (e.g. waveform lines), finding edges of lines makes double lines.
        # Given standard App Icons, the symbol is usually a filled shape (Glyph).
        # So we should FIND EDGES of the Glyph to get the Outline Style.
        
        edges = symbol_mask.filter(ImageFilter.FIND_EDGES)
        
        # Thicken the edges
        # 400px -> 44px (Ratio ~9)
        # 1.5px stroke -> ~13px dilation
        stroke_width = 13
        thick_edges = edges.filter(ImageFilter.MaxFilter(stroke_width))
        
        # Also keep any "internal" details if they are thin lines?
        # If the symbol has internal waveform lines that are thin, FIND_EDGES on distinct lines makes double lines.
        # Maybe we should just output the Symbol Mask itself first and see?
        # User previously said "V6 is confirmed but ugly". V6 was "Smart Outline".
        # V6 logic was: Body - ErodedBody.
        # If I output the Symbol Mask converted to Outline, it matches User's desire for "Hollow".
        
        # Let's do: Outline of the Symbol.
        
        final_mask = thick_edges
        
        # Create Final Black Template
        black = Image.new("RGB", (width, height), (0, 0, 0))
        final = black.convert("RGBA")
        final.putalpha(final_mask)
        
        # Resize to Target
        content_size = 38
        content = final.resize((content_size, content_size), Image.Resampling.LANCZOS)
        
        canvas = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
        offset = (44 - content_size) // 2
        canvas.paste(content, (offset, offset))
        
        # Force Clean Edges
        p = canvas.load()
        for i in range(44):
            p[i,0]=(0,0,0,0); p[i,43]=(0,0,0,0)
            p[0,i]=(0,0,0,0); p[43,i]=(0,0,0,0)
            
        canvas.save(output_path)
        print(f"Success! White Symbol Extracted to {output_path}")
        
    except Exception as e:
        print(e)

extract_white_symbol('assets/app_icon.png', 'assets/tray_icon_v10.png')
