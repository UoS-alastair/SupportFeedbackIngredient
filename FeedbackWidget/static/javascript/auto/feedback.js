(function () {
    // Configured to point directly to the EPrints CGI endpoint
    const ENDPOINT_URL = "/cgi/feedback";

    // Build UI Container
    const container = document.createElement("div");
    container.id = "fb-widget-root";
    container.innerHTML = `
    <button id="fb-trigger-btn" aria-label="Open feedback form">Support</button>
    <div id="fb-modal" class="fb-hidden">
      <div class="fb-header">
        <h3>Contact Repository Support</h3>
        <button id="fb-close-btn" type="button">&times;</button>
      </div>
      <div id="fb-message" class="fb-message fb-hidden" role="status" aria-live="polite"></div>
      <form id="fb-form">
        <div class="fb-field">
          <label for="fb-name">Name<span class="fb-required">*</span></label>
          <input type="text" id="fb-name" required />
        </div>
        <div class="fb-field">
          <label for="fb-email">Email<span class="fb-required">*</span></label>
          <input type="email" id="fb-email" required />
        </div>
        <div class="fb-field">
          <label for="fb-comment">Issue<span class="fb-required">*</span></label>
          <textarea id="fb-comment" rows="3" required></textarea>
        </div>
        
        <div class="fb-field">
          <label>Screenshot</label>
          <div id="fb-screenshot-controls">
            <button type="button" id="fb-capture-btn">Capture Screen</button>
            <span id="fb-capture-status"></span>
          </div>
          <div id="fb-upload-wrapper" class="fb-hidden">
            <p class="fb-hint">Screen capture unavailable. Please upload manually:</p>
            <input type="file" id="fb-file-input" accept="image/*" />
          </div>
          <div id="fb-preview-container" class="fb-hidden">
            <img id="fb-preview-img" alt="Screenshot preview" />
            <button type="button" id="fb-remove-img">Remove</button>
          </div>
        </div>

        <button type="submit" id="fb-submit-btn">Submit Feedback</button>
      </form>
    </div>
  `;

    // Pages may be static, so ask the endpoint whether the current user is permitted
    async function isPermitted() {
        try {
            const response = await fetch(ENDPOINT_URL, {
                method: "GET",
                cache: "no-store",
                credentials: "same-origin",
            });
            const result = await response.json();
            return response.ok && result.permitted === true;
        } catch (err) {
            return false;
        }
    }

    document.addEventListener("DOMContentLoaded", async () => {
        if (!(await isPermitted())) {
            return;
        }
        document.body.appendChild(container);
        initWidget();
    });

    function initWidget() {
        const triggerBtn = document.getElementById("fb-trigger-btn");
        const modal = document.getElementById("fb-modal");
        const closeBtn = document.getElementById("fb-close-btn");
        const form = document.getElementById("fb-form");
        const messageEl = document.getElementById("fb-message");
        const captureBtn = document.getElementById("fb-capture-btn");
        const captureStatus = document.getElementById("fb-capture-status");
        const uploadWrapper = document.getElementById("fb-upload-wrapper");
        const fileInput = document.getElementById("fb-file-input");
        const previewContainer = document.getElementById("fb-preview-container");
        const previewImg = document.getElementById("fb-preview-img");
        const removeImgBtn = document.getElementById("fb-remove-img");

        let screenshotBase64 = null;
        let screenshotFile = null;

        triggerBtn.addEventListener("click", () => modal.classList.toggle("fb-hidden"));
        closeBtn.addEventListener("click", () => modal.classList.add("fb-hidden"));

        function getBrowserAndOS() {
            const ua = navigator.userAgent;
            let os = "Unknown OS";
            let browser = "Unknown Browser";

            if (ua.indexOf("Win") !== -1) os = "Windows";
            else if (ua.indexOf("Mac") !== -1) os = "macOS";
            else if (ua.indexOf("Linux") !== -1) os = "Linux";
            else if (ua.indexOf("Android") !== -1) os = "Android";
            else if (ua.indexOf("like Mac") !== -1) os = "iOS";

            if (ua.indexOf("Firefox") !== -1) browser = "Firefox";
            else if (ua.indexOf("Chrome") !== -1) browser = "Chrome";
            else if (ua.indexOf("Safari") !== -1) browser = "Safari";
            else if (ua.indexOf("Edge") !== -1) browser = "Edge";

            return { os, browser };
        }

        function getUserDetails() {
            return {
                id: window.eprints_logged_in_userid ?? 0,
                username: window.eprints_logged_in_username ?? "",
                usertype: window.eprints_logged_in_usertype ?? "",
            };
        }

        function getUrlParams() {
            const params = {};
            const urlParams = new URLSearchParams(window.location.search);
            for (const [key, value] of urlParams.entries()) {
                params[key] = value;
            }
            return params;
        }

        async function captureNativeScreen() {
            const stream = await navigator.mediaDevices.getDisplayMedia({
                video: {
                    displaySurface: "browser",
                },
                audio: false,
                preferCurrentTab: true,
                selfBrowserSurface: "include",
                systemAudio: "exclude",
                surfaceSwitching: "exclude"
            });

            const video = document.createElement("video");
            video.srcObject = stream;
            await video.play();

            const canvas = document.createElement("canvas");
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            const ctx = canvas.getContext("2d");
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

            stream.getTracks().forEach((track) => track.stop());
            return canvas.toDataURL("image/png");
        }

        captureBtn.addEventListener("click", async () => {
            captureStatus.textContent = "Capturing...";
            modal.classList.add("fb-hidden");

            try {
                console.log("Capturing " + captureStatus.textContent);
                if (navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia) {
                    screenshotBase64 = await captureNativeScreen();
                    screenshotFile = null;
                    showPreview(screenshotBase64);
                    captureStatus.textContent = "";
                    modal.classList.remove("fb-hidden");
                    return;
                }
            } catch (err) {
                console.warn("Screen Capture failed, dropping to fallback.", err);
            }

            modal.classList.remove("fb-hidden");
            captureStatus.textContent = "";
            uploadWrapper.classList.remove("fb-hidden");
        });

        fileInput.addEventListener("change", (e) => {
            const file = e.target.files[0];
            if (file) {
                screenshotFile = file;
                const reader = new FileReader();
                reader.onload = (event) => {
                    screenshotBase64 = event.target.result;
                    showPreview(screenshotBase64);
                };
                reader.readAsDataURL(file);
            }
        });

        function showPreview(dataUrl) {
            previewImg.src = dataUrl;
            previewContainer.classList.remove("fb-hidden");
        }

        function displayMessage(message, type = "info") {
            messageEl.textContent = message;
            messageEl.className = `fb-message fb-message-${type}`;
            messageEl.classList.toggle("fb-hidden", !message);
            form.outerHTML = '';
        }

        function resetFeedbackForm() {
            form.reset();
            removeImgBtn.click();
            uploadWrapper.classList.add("fb-hidden");
        }

        removeImgBtn.addEventListener("click", () => {
            screenshotBase64 = null;
            screenshotFile = null;
            fileInput.value = "";
            previewImg.src = "";
            previewContainer.classList.add("fb-hidden");
        });

        form.addEventListener("submit", async (e) => {
            e.preventDefault();

            const { os, browser } = getBrowserAndOS();

            const payload = {
                eprintsUser: getUserDetails(),
                user: {
                    name: document.getElementById("fb-name").value,
                    email: document.getElementById("fb-email").value,
                    comment: document.getElementById("fb-comment").value,
                },
                device: {
                    os: os,
                    browser: browser,
                    userAgent: navigator.userAgent,
                    screenResolution: `${window.screen.width}x${window.screen.height}`,
                    viewportSize: `${window.innerWidth}x${window.innerHeight}`,
                    devicePixelRatio: window.devicePixelRatio || 1,
                },
                page: {
                    fullUrl: window.location.href,
                    pathname: window.location.pathname,
                    queryParams: getUrlParams(),
                },
            };

            try {
                displayMessage("");
                const formData = new FormData();
                formData.append("payload", JSON.stringify(payload));

                if (screenshotFile || screenshotBase64) {
                    const screenshot = screenshotFile || await (await fetch(screenshotBase64)).blob();
                    const filename = screenshotFile ? screenshotFile.name : "screenshot.png";
                    formData.append("screenshot", screenshot, filename);
                }

                const response = await fetch(ENDPOINT_URL, {
                    method: "POST",
                    body: formData,
                });
                const result = await response.json().catch(() => null);

                if (response.ok && result && result.status === "success") {
                    resetFeedbackForm();
                    displayMessage("Thank you for your feedback!", "success");
                } else {
                    const message = result && typeof result.message === "string"
                        ? result.message
                        : "Failed to send feedback.";
                    resetFeedbackForm();
                    displayMessage(message, "error");
                }
            } catch (err) {
                console.error("Submission error:", err);
                resetFeedbackForm();
                displayMessage("An error occurred while submitting feedback.", "error");
            }
        });
    }
})();