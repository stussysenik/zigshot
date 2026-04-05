import AppKit
import CZigShot

// Verify the C API is accessible
print("libzigshot linked. Testing image creation...")
if let img = zs_image_create_empty(100, 100) {
    let w = zs_image_get_width(img)
    let h = zs_image_get_height(img)
    print("Created \(w)x\(h) image successfully.")
    zs_image_destroy(img)
} else {
    print("ERROR: Failed to create image.")
}

print("ZigShot app scaffolding complete.")
