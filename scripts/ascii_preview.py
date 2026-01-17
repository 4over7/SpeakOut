from PIL import Image
import sys

def ascii_view(path):
    try:
        img = Image.open(path).convert("RGBA")
        original_width, original_height = img.size
        print(f"Inspecting {path} ({original_width}x{original_height})")
        
        # Resize to 64x64 for ASCII view if too big
        target_size = 64
        img = img.resize((target_size, target_size), Image.Resampling.BILINEAR)
        width, height = img.size
        
        # Analyze Alpha or Luminance
        has_transparency = False
        # Check center pixel alpha
        if img.getpixel((width//2, height//2))[3] < 255:
            has_transparency = True
            
        for y in range(height):
            line = ""
            for x in range(width):
                r,g,b,a = img.getpixel((x,y))
                if has_transparency:
                    if a < 50: line += "  "
                    elif a < 200: line += ".."
                    else: line += "##"
                else:
                    # Luminance mode for Opaque icons (App Icon)
                    lum = (r+g+b)//3
                    if lum < 50: line += "##" # Dark
                    elif lum < 200: line += "::" # Mid
                    else: line += ".." # Light (White)
            print(f"{y:02d} {line}")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        ascii_view(sys.argv[1])
