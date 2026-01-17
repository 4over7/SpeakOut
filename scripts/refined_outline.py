from PIL import Image, ImageFilter, ImageChops
import collections

def refine_outline(input_path, output_path):
    print(f"Generating Outline from Correct Shape {input_path}...")
    try:
        # Load the Source Shape (V5 - Solid Black Bubble)
        # This image is likely 44x44 or similar small size.
        img = Image.open(input_path).convert("RGBA")
        
        # Upscale to 200x200 to allow for smooth edge dilation
        # Nearest Neighbor to keep sharp edges initially, then smooth? 
        # Actually, Lanczos is fine if we threshold it.
        work_size = 200
        img = img.resize((work_size, work_size), Image.Resampling.LANCZOS)
        
        # Extract the Body Mask (Alpha > 10)
        # Since V5 is black on transparent, Alpha is our guide.
        r,g,b,alpha = img.split()
        
        # Binarize Alpha to get a crisp mask
        body_mask = alpha.point(lambda p: 255 if p > 50 else 0)
        
        # 1. FIND EDGES
        edges = body_mask.filter(ImageFilter.FIND_EDGES)
        
        # 2. WAVEFORM (Holes inside the body)
        # If V5 was solid black, we LOST the waveform?
        # User said V5 was "A Black Block". 
        # IF V5 HAS NO WAVEFORM, WE MUST RECOVER IT.
        # But we don't have a good source for the waveform aligned to V5 if V5 is just a silhouette.
        # WAIT, User said "V4 shape is correct". 
        # Checking logic: Did V4 have waveform? Yes.
        # Did V5 preserve it? Step 13288: "Convert ... into a pure black template icon".
        # If I converted it blindly, I might have kept the waveform transparency?
        # Let's assume V5 Alpha Channel has the holes.
        # If not, we are in trouble. But `tray_icon_smart.png` (Step 13329) DEFINITELY had the waveform.
        # Let's try to use 'assets/tray_icon_smart.png' as source if V5 fails?
        # Actually, let's use `tray_icon_smart.png` logic on the 'source' image?
        # No, let's assume `tray_icon_source_shape.png` (V5) has the holes.
        # If 'body_mask' has holes (0), then FIND_EDGES will find lines there too.
        # So 'edges' will contain both Outer Outline and Inner Waveform Outline.
        
        # 3. DILATE (Thicken)
        # 200px size -> 44px target (Ratio ~4.5)
        # to get 1.5px thickness -> Need ~7px stroke
        stroke_width = 7
        thick_edges = edges.filter(ImageFilter.MaxFilter(stroke_width))
        
        # 4. Final Composition
        black = Image.new("RGB", (work_size, work_size), (0, 0, 0))
        final = black.convert("RGBA")
        final.putalpha(thick_edges)
        
        # Resize to Target
        target_size = 44
        final_sized = final.resize((target_size, target_size), Image.Resampling.LANCZOS)
        
        final_sized.save(output_path)
        print(f"Success! Outline from V5 saved to {output_path}")

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

refine_outline('assets/tray_icon_source_shape.png', 'assets/tray_icon_v8.png')
