# VYBE 2.0.6 — QR Close & Screenshot AI

## QR viewer
- Added a visible close (X) control and a Close button to the generated QR panel.
- Escape also closes the QR panel.
- The same utility panel can now be safely reused for later QR or screenshot results.

## Screenshot AI
- Replaced the previous screen-region OCR/Vision pipeline.
- The radial action is now named Screenshot AI.
- Activating it launches the macOS interactive screenshot selector (`/usr/sbin/screencapture -i -x`). The user chooses the exact area to capture; cancelling exits without uploading anything.
- VYBE displays the captured image and sends it as an image input to the currently selected OpenRouter model, together with a prompt to explain the screenshot.
- Displays the AI analysis beside/below the screenshot in a closeable panel.
- Screenshot temporary file is deleted after the AI request completes or fails.
- Removed the local Vision OCR import and no longer performs background/continuous screen reading.

## Privacy and model compatibility
- The selected screenshot is transmitted to OpenRouter and the selected model for analysis. Do not capture passwords, private messages, financial information, or other sensitive content unless you intend to share it with that service.
- The selected free model must support image input. If it does not, VYBE displays the provider/model error and keeps the screenshot visible until the panel is closed.
- This flow uses a user-initiated screenshot selector, not continuous screen capture.
