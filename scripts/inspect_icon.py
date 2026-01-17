from PIL import Image

def check_icon():
    try:
        img = Image.open('assets/tray_icon.png').convert("RGBA")
        print(f"Image mode: {img.mode}, Size: {img.size}")
        
        # Check corners (should be Transparent)
        corners = [(0,0), (0, img.height-1), (img.width-1, 0), (img.width-1, img.height-1)]
        for x,y in corners:
            pixel = img.getpixel((x,y))
            print(f"Corner Pixel at ({x},{y}): {pixel}")
            
        # Check center (should be Black)
        center_x, center_y = img.width // 2, img.height // 2
        center = img.getpixel((center_x, center_y))
        print(f"Center Pixel at ({center_x},{center_y}): {center}")
        
    except Exception as e:
        print(f"Error: {e}")

check_icon()
