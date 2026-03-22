/**
 * Gemini Deep Research CSS Selector Registry
 *
 * All selectors for the Deep Research UI flow are centralized here.
 * When Google updates the Gemini UI, only this file needs updating.
 * Each entry is an array of fallback selectors tried in order.
 */

export const SELECTORS = {
  /** The main text input area.
   *  Verified 2026-03-04: div.ql-editor with contenteditable, aria-label="Enter a prompt for Gemini",
   *  data-placeholder changes to "What do you want to research?" in Deep Research mode. */
  INPUT: [
    'div[contenteditable="true"]',
    '[aria-label="Enter a prompt for Gemini"]',
    'div[role="textbox"]',
    "rich-textarea .ql-editor",
    "textarea",
    '[aria-label*="prompt"]',
  ],

  /** Step 1: Click "Tools" button to open the toolbox drawer.
   *  Verified 2026-03-04: button with aria-label="Tools" in the input area.
   *  Updated 2026-03-13: aria-label removed from Tools button; now uses class toolbox-drawer-button
   *  and visible text "Tools". Selector order: class-based first, text fallback. */
  TOOLS_BUTTON: [
    'button.toolbox-drawer-button',
    'button:has-text("Tools")',
    'button[aria-label="Tools"]',
    '.input-area button[aria-label="Tools"]',
  ],

  /** Step 2: Click "Deep research" item inside the toolbox drawer overlay.
   *  Verified 2026-03-04: <toolbox-drawer-item> containing a button, text "Deep research".
   *  Located inside cdk-overlay-pane > mat-card > mat-action-list. */
  DEEP_RESEARCH_TRIGGER: [
    'toolbox-drawer-item button:has-text("Deep research")',
    '.toolbox-drawer-card button:has-text("Deep research")',
    'mat-action-list button:has-text("Deep research")',
    '.cdk-overlay-pane button:has-text("Deep research")',
    'button:has-text("Deep research")',
  ],

  /** Verification: Deep Research mode is active — the deselect chip appears.
   *  Verified 2026-03-04: button with aria-label="Deselect Deep research",
   *  class includes "toolbox-drawer-item-deselect-button". */
  DEEP_RESEARCH_ACTIVE: [
    'button[aria-label="Deselect Deep research"]',
    '.toolbox-drawer-item-deselect-button',
    'button:has-text("Deep research"):not(.toolbox-drawer-card button)',
  ],

  /** The send/submit button — appears after typing text in Deep Research mode.
   *  Verified 2026-03-04: button with aria-label="Send message", class="send-button". */
  SEND: [
    'button[aria-label="Send message"]',
    'button.send-button',
    'button[aria-label*="Send"]',
    'button[aria-label*="send"]',
    'button[type="submit"]',
  ],

  /** "Start research" / confirm button on the research plan page.
   *  Verified 2026-03-04: button with data-test-id="confirm-button",
   *  aria-label="start research", text "Start research". */
  CONFIRM_RESEARCH: [
    'button[data-test-id="confirm-button"]',
    'button[aria-label="start research"]',
    'button:has-text("Start research")',
    'button:has-text("Start Research")',
  ],

  /** Edit plan button — appears alongside confirm on the research plan page.
   *  Verified 2026-03-04: button with data-test-id="edit-button",
   *  aria-label="edit the research plan". */
  EDIT_PLAN: [
    'button[data-test-id="edit-button"]',
    'button[aria-label="edit the research plan"]',
    'button:has-text("Edit plan")',
  ],

  /** Research plan container — the steps appear inside the model response area.
   *  Verified 2026-03-04: div.research-step with div.research-step-title children.
   *  Steps: "Research Websites", "Analyze Results", "Create Report". */
  RESEARCH_PLAN: [
    'div[class*="research-step"]',
    'div.research-step-title',
    '[data-test-id*="research-plan"]',
  ],

  /** Progress indicator — spinner visible while plan is generating and during research.
   *  Verified 2026-03-04: div.avatar_spinner_animation visible during plan generation.
   *  Stop button aria-label contains "Stop" during active research. */
  PROGRESS_INDICATOR: [
    'div[class*="avatar_spinner_animation"]',
    '[class*="progress"]',
    '[role="progressbar"]',
    'button[aria-label*="Stop"]',
    'button:has-text("Stop")',
  ],

  /** Completion signal — mic button reappears when generation finishes.
   *  Verified 2026-03-04: button with data-node-type="speech_dictation_mic_button". */
  MIC_BUTTON: [
    'button[data-node-type="speech_dictation_mic_button"]',
    'button[aria-label="Microphone"]',
  ],

  /** The final report container — the large markdown element (44k+ chars).
   *  Verified 2026-03-05: .markdown.markdown-main-panel inside MESSAGE-CONTENT.
   *  The longest markdown element is the report; the shorter ones are plan/completion text.
   *  Note: response-container only holds the plan (1316 chars), NOT the report. */
  REPORT: [
    ".markdown.markdown-main-panel",
    'MESSAGE-CONTENT .markdown',
    '[class*="response-content"]',
    '[data-message-author="model"]',
  ],

  /** Share conversation button — visible during AND after research.
   *  Verified 2026-03-05: button with data-test-id="share-button",
   *  aria-label="Share conversation". */
  SHARE_BUTTON: [
    'button[data-test-id="share-button"]',
    'button[aria-label="Share conversation"]',
  ],

  /** Share dialog — opens as cdk-overlay-pane > mat-dialog with create-social-media-dialog.
   *  Verified 2026-03-05: dialog shows "Creating link..." then renders the share URL.
   *  The link appears as text containing "gemini.google.com/share/{id}". */
  SHARE_DIALOG: [
    "create-social-media-dialog",
    '.share-dialog',
    'mat-dialog-container',
  ],

  /** Copy link button inside the share dialog.
   *  Verified 2026-03-05: button with data-test-id="copy-link", aria-label="Copy link". */
  COPY_LINK: [
    'button[data-test-id="copy-link"]',
    'button[aria-label="Copy link"]',
  ],

  /** Export/copy button on the completed report.
   *  Verified 2026-03-05: "Copy prompt" buttons visible (data-test-id not set). */
  EXPORT: [
    'button[aria-label*="Export"]',
    'button[aria-label*="Copy"]',
    'button:has-text("Export")',
    'button:has-text("Copy to Docs")',
  ],
} as const;

export type SelectorGroup = keyof typeof SELECTORS;
