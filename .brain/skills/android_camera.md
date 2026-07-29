# .brain/skills/android_camera.md - ANDROID CAMERA & OEM HARDWARE ARCHITECTURE

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

When this skill is activated at Gate 0, you must enforce low-latency frame pipelines, correct logical-to-physical camera bindings, proper OEM extension querying, and strict memory/lifecycle hygiene.

## 1. Low-Latency Viewfinder & Rendering Pipelines
- **Viewfinder Render Surface**: You must use `SurfaceView` instead of `TextureView` for the main camera viewfinder unless dynamic alpha animations, scaling, or cropping require view hierarchy integration. `SurfaceView` renders directly to a hardware compositor overlay, yielding zero-frame render latency and significantly reduced CPU overhead.
- **Asynchronous Image Analysis**: Run all pixel analysis or frame processing (e.g. `ImageReader`) on a dedicated background `HandlerThread` or a specialized coroutine dispatcher. Running image processing on the main application thread will drop frame rates and cause UI jitter.
- **Direct Hardware Buffers**: For high-performance graphics, pass `android.hardware.HardwareBuffer` objects directly to C++/Vulkan pipelines via JNI/NDK, avoiding intermediate pixel-array allocations and memory copies.

## 2. Multi-Camera & Physical Sensor Targeting
- **Logical Group Decomposition**: Always check for `CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA` before querying physical IDs. Do not assume hardcoded physical ID indexes.
- **Stream Binding**: To access specific lenses (wide, periscope telephoto, ultrawide) on a multi-camera device, create a single capture session on the logical camera and bind the preview/capture streams using `OutputConfiguration.setPhysicalCameraId(physicalId)`. Opening multiple physical camera IDs directly using `openCamera()` is restricted by ColorOS and will throw a security exception.
- **Maximum Resolution (200MP/50MP) Capture**:
  - Check `StreamConfigurationMap.getHighResolutionOutputSizes()` to retrieve the full unbinned sensor sizes.
  - Set the capture request key `CaptureRequest.SENSOR_PIXEL_MODE` to `CameraMetadata.SENSOR_PIXEL_MODE_MAXIMUM_RESOLUTION` (API 32+) when capturing photos, and ensure the session is configured to support max-resolution modes.

## 3. OEM Extensions & ColorOS CameraUnit Integration
- **Extension Availability Guards**: Prior to initiating an extension session (like HDR or Night Mode), you must query availability using `CameraExtensionCharacteristics.isExtensionSupported()` (API 31+) or `ExtensionsManager.isExtensionAvailable()` (CameraX). Do not try to open an extension session without confirming support, as it will crash the camera framework.
- **Graceful Fallback**: If an extension creation fails or is unsupported at runtime, fall back automatically and silently to a standard `CameraCaptureSession` to ensure the application remains functional.
- **Stabilization Override**: To enable Oppo Ultra-Steady or Video stabilization pro, check for available stabilization modes (`CONTROL_VIDEO_STABILIZATION_MODE_ON` and `LENS_OPTICAL_STABILIZATION_MODE_ON`). If proprietary modes are needed, bridge them via the Oppo `CameraUnit` SDK wrappers.

## 4. Strict Resource Lifecycle & Memory Hygiene
- **Immediate Frame Disposal**: Every `Image` object acquired from `ImageReader` must be closed inside a `try-with-resources` or `use` block, ensuring `Image.close()` is called immediately. If a single frame is leaked, the camera framework will run out of buffers and freeze the viewfinder.
- **Asynchronous Release**: Camera devices (`CameraDevice`) and capture sessions (`CameraCaptureSession`) must be closed on the background thread during lifecycle callbacks (`onPause()` or `onDestroy()`). Do not block the main UI thread during close operations.

## 5. Video + Concurrency Constraints (harvested from renocore-camera Phase 3, 2026-07-17)
- **Max-res and video cannot coexist on the OEM HAL**: configuring `SENSOR_PIXEL_MODE_MAXIMUM_RESOLUTION` (50MP/200MP) on the `ImageReader` stream while a `MediaRecorder` video surface is attached to the same logical session crashes the MediaTek/Oppo ISP (`libmtkcam.featurepipe.streaming.so`, fatal `SIGSEGV`) — the streaming pipeline cannot multiplex unbinned sensor streams and a video encoder. In video mode, force `enableHighRes = false` before resolving the `ImageReader` size (fall back to binned), and do NOT call `OutputConfiguration.setPhysicalCameraId()` on the video surface. (L-010)
- **No pipeline mutation during active recording**: hardware pipeline mutators (`selectLens`, `toggleExtension`, `setHighResEnabled`) must early-return while recording (`if (isRecordingVideo) return`) — reconfiguring streams mid-record corrupts the encoder session.
- **Off-thread MediaStore queries**: gallery/media queries run on `Dispatchers.IO` with sorted `Cursor` flows; a flat query loop on the main thread freezes the UI.
- **Monotonic 3A watchdogs**: 3A pre-capture handlers must guard on a monotonic `captureSequenceId`; non-monotonic hardware callbacks otherwise deadlock the autofocus synchronization loop.
- **Lock manual controls when an extension owns exposure**: manual ISO/shutter/focus sliders must visibly lock out while a vendor extension (Night/Bokeh/HDR) controls 3A, or the two fight for the same hardware keys.
- **KNOWN HAZARD (unresolved, L-013 in child):** switching into video or extension modes can freeze the app — suspected main-thread blocking IPC on `getCameraExtensionCharacteristics()` or a session-reconfiguration deadlock in `closeActiveSessions()`. Query extension characteristics OFF the main thread and serialize session teardown; treat mode-switch reconfiguration as a prime deadlock suspect until proven otherwise.
