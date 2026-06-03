type MissingItem = {
  item: string;
  label?: string;
  image: string;
  imageFile?: string;
};

type UnusedImage = {
  name: string;
  fileName: string;
  url?: string;
};

type ScanReport = {
  inventory: string;
  imageDirectory: string;
  itemCount: number;
  imageCount: number;
  missingItems: MissingItem[];
  unusedImages: string[];
  unusedImageEntries?: UnusedImage[];
  warnings: string[];
  reportUnusedImages: boolean;
  scannedRoots?: number;
  totalRoots?: number;
  scannedPaths?: number;
  canceled?: boolean;
};

type OpenPayload = {
  inventory?: string;
  caseSensitive?: boolean;
  reportUnusedImages?: boolean;
};

type NuiResponse =
  | { ok: true; report: ScanReport }
  | { ok: false; error?: string };

type GiveItemResponse =
  | { ok: true; message?: string }
  | { ok: false; error?: string };

type CancelScanResponse =
  | { ok: true; message?: string }
  | { ok: false; error?: string };

type ScanProgress = {
  phase?: 'running' | 'complete' | 'canceled';
  scannedRoots?: number;
  totalRoots?: number;
  scannedPaths?: number;
  missingItems?: number;
  unusedImages?: number;
};

export {};

declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
}

const resourceName = window.GetParentResourceName?.() ?? 'clx_imagedetector';

const scanButton = document.querySelector<HTMLButtonElement>('#scanButton');
const closeButton = document.querySelector<HTMLButtonElement>('#closeButton');
const statusBar = document.querySelector<HTMLElement>('#statusBar');
const progressPanel = document.querySelector<HTMLElement>('#progressPanel');
const progressLabel = document.querySelector<HTMLElement>('#progressLabel');
const etaValue = document.querySelector<HTMLElement>('#etaValue');
const progressBar = document.querySelector<HTMLElement>('#progressBar');
const statGrid = document.querySelector<HTMLElement>('#statGrid');
const missingValue = document.querySelector<HTMLElement>('#missingValue');
const unusedValue = document.querySelector<HTMLElement>('#unusedValue');
const missingSearch = document.querySelector<HTMLInputElement>('#missingSearch');
const unusedSearch = document.querySelector<HTMLInputElement>('#unusedSearch');
const scanState = document.querySelector<HTMLElement>('#scanState');
const imageWorkspace = document.querySelector<HTMLElement>('#imageWorkspace');
const missingList = document.querySelector<HTMLElement>('#missingList');
const unusedList = document.querySelector<HTMLElement>('#unusedList');

const scanningBaseMessage = 'Please be patient';
const scanningMessages: readonly string[] = [
  'Go and touch some grass while your waiting',
  'Get a cup of coffee while your waiting',
  'Stay hydrated!',
  'How was your day?',
  'BOO! Did I scare you?',
];

let currentReport: ScanReport | null = null;
let scanStartedAt = 0;
let isScanning = false;
let cancelRequested = false;
let scanningMessageInterval = 0;
let scanningMessageResetTimeout = 0;
let lastScanningMessageIndex = -1;

// Keep status class names explicit so Tailwind includes every state in the production build.
const statusClasses = {
  info: 'status-info',
  error: 'status-error',
  success: 'status-success',
} as const;

async function nui<TResponse>(eventName: string, data: unknown = {}): Promise<TResponse> {
  const response = await fetch(`https://${resourceName}/${eventName}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=UTF-8',
    },
    body: JSON.stringify(data),
  });

  return response.json() as Promise<TResponse>;
}

function setText(element: HTMLElement | null, value: string | number): void {
  if (!element) return;
  element.textContent = String(value);
}

function hideStats(): void {
  statGrid?.classList.add('hidden');
}

function showStats(): void {
  statGrid?.classList.remove('hidden');
}

function setStats(missingCount: number, unusedCount: number): void {
  setText(missingValue, Math.max(0, missingCount));
  setText(unusedValue, Math.max(0, unusedCount));
}

function updateStatsFromProgress(progress: ScanProgress): void {
  if (typeof progress.missingItems !== 'number' && typeof progress.unusedImages !== 'number') {
    return;
  }

  showStats();

  if (typeof progress.missingItems === 'number') {
    setText(missingValue, Math.max(0, progress.missingItems));
  }

  if (typeof progress.unusedImages === 'number') {
    setText(unusedValue, Math.max(0, progress.unusedImages));
  }
}

function setStatus(message: string, type: 'info' | 'error' | 'success' = 'info'): void {
  if (!statusBar) return;

  statusBar.className = `clx-status-bar ${statusClasses[type]}`;
  statusBar.textContent = message;
  statusBar.classList.remove('hidden');
}

function clearStatus(): void {
  if (!statusBar) return;

  statusBar.textContent = '';
  statusBar.classList.add('hidden');
}

function setLoading(isLoading: boolean, isCanceling = false): void {
  if (!scanButton) return;

  scanButton.disabled = isCanceling;
  scanButton.textContent = isCanceling ? 'Canceling...' : isLoading ? 'Cancel' : 'Scan';
  scanButton.classList.toggle('is-danger', isLoading && !isCanceling);
  scanButton.classList.toggle('is-pending', isCanceling);
}

function formatDuration(milliseconds: number): string {
  if (!Number.isFinite(milliseconds) || milliseconds < 0) {
    return 'calculating';
  }

  const totalSeconds = Math.ceil(milliseconds / 1000);

  if (totalSeconds <= 0) {
    return '0s';
  }

  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  if (minutes <= 0) {
    return `${seconds}s`;
  }

  return `${minutes}m ${seconds.toString().padStart(2, '0')}s`;
}

function resetProgress(): void {
  scanStartedAt = 0;
  progressPanel?.classList.add('hidden');
  setText(progressLabel, 'Scan progress');
  setText(etaValue, 'Estimated remaining: calculating');

  if (progressBar) {
    progressBar.style.width = '0%';
  }
}

function renderScanProgress(progress: ScanProgress): void {
  if (progress.phase === 'complete') {
    resetProgress();
    return;
  }

  updateStatsFromProgress(progress);

  const totalRoots = Math.max(0, progress.totalRoots ?? 0);
  const scannedRoots = Math.min(totalRoots, Math.max(0, progress.scannedRoots ?? 0));
  const scannedPaths = Math.max(0, progress.scannedPaths ?? 0);
  const percent = totalRoots > 0 ? Math.min(100, (scannedRoots / totalRoots) * 100) : 0;

  if (scanStartedAt <= 0) {
    scanStartedAt = Date.now();
  }

  let remainingText = 'calculating';

  if (progress.phase === 'canceled') {
    remainingText = 'canceled';
  } else if (totalRoots > 0 && scannedRoots >= totalRoots) {
    remainingText = '0s';
  } else if (scannedRoots > 0 && totalRoots > scannedRoots) {
    const elapsed = Date.now() - scanStartedAt;
    const averageRootTime = elapsed / scannedRoots;
    remainingText = formatDuration(averageRootTime * (totalRoots - scannedRoots));
  }

  progressPanel?.classList.remove('hidden');
  const labelPrefix = progress.phase === 'canceled' ? 'Scan canceled' : 'Scan progress';
  setText(progressLabel, totalRoots > 0
    ? `${labelPrefix}: ${scannedRoots}/${totalRoots} roots, ${scannedPaths} files`
    : `${labelPrefix}: ${scannedPaths} files`);
  setText(etaValue, `Estimated remaining: ${remainingText}`);

  if (progressBar) {
    progressBar.style.width = `${percent}%`;
  }
}

function createEmptyRow(message: string): HTMLDivElement {
  const row = document.createElement('div');
  row.className = 'result-row-muted';
  row.textContent = message;
  return row;
}

function createScanningRow(): HTMLDivElement {
  const row = document.createElement('div');
  row.className = 'result-row-loading';

  const content = document.createElement('div');
  content.className = 'loading-content';

  const title = document.createElement('div');
  title.className = 'loading-title';
  title.append('Scanning');

  for (let index = 0; index < 3; index += 1) {
    const dot = document.createElement('span');
    dot.className = 'loading-dot';
    dot.textContent = '.';
    title.appendChild(dot);
  }

  const hint = document.createElement('p');
  hint.id = 'scanningHint';
  hint.className = 'loading-hint';
  hint.textContent = scanningBaseMessage;

  content.append(title, hint);
  row.appendChild(content);
  return row;
}

function stopScanningMessages(): void {
  window.clearInterval(scanningMessageInterval);
  window.clearTimeout(scanningMessageResetTimeout);

  scanningMessageInterval = 0;
  scanningMessageResetTimeout = 0;
  lastScanningMessageIndex = -1;
}

function getNextScanningMessage(): string {
  if (scanningMessages.length === 1) {
    lastScanningMessageIndex = 0;
    return scanningMessages[0];
  }

  let index = Math.floor(Math.random() * scanningMessages.length);

  while (index === lastScanningMessageIndex) {
    index = Math.floor(Math.random() * scanningMessages.length);
  }

  lastScanningMessageIndex = index;
  return scanningMessages[index];
}

function startScanningMessages(): void {
  stopScanningMessages();

  scanningMessageInterval = window.setInterval(() => {
    const hint = document.querySelector<HTMLElement>('#scanningHint');

    if (!hint || !isScanning) {
      stopScanningMessages();
      return;
    }

    hint.textContent = getNextScanningMessage();
    window.clearTimeout(scanningMessageResetTimeout);

    scanningMessageResetTimeout = window.setTimeout(() => {
      const currentHint = document.querySelector<HTMLElement>('#scanningHint');

      if (currentHint && isScanning) {
        currentHint.textContent = scanningBaseMessage;
      }
    }, 2600);
  }, 7200);
}

function getSearchQuery(input: HTMLInputElement | null): string {
  return input?.value.trim().toLowerCase() ?? '';
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function createWildcardRegex(query: string): RegExp {
  const pattern = query.split('*').map(escapeRegex).join('.*');
  return new RegExp(pattern);
}

function matchesSearch(values: Array<string | undefined>, query: string): boolean {
  if (query === '') return true;

  const wildcardRegex = query.includes('*') ? createWildcardRegex(query) : null;

  return values.some((value) => {
    if (!value) return false;

    const normalizedValue = value.toLowerCase();
    return wildcardRegex
      ? wildcardRegex.test(normalizedValue)
      : normalizedValue.includes(query);
  });
}

function matchesMissingItem(entry: MissingItem, query: string): boolean {
  return matchesSearch([entry.item, entry.label, entry.image, entry.imageFile], query);
}

function matchesUnusedImage(entry: UnusedImage, query: string): boolean {
  return matchesSearch([entry.name, entry.fileName], query);
}

function renderList<TValue>(
  container: HTMLElement | null,
  values: TValue[],
  emptyMessage: string,
  renderValue: (value: TValue) => string,
): void {
  if (!container) return;

  container.innerHTML = '';

  if (values.length === 0) {
    container.appendChild(createEmptyRow(emptyMessage));
    return;
  }

  for (const value of values) {
    const row = document.createElement('div');
    row.className = 'result-row';
    row.textContent = renderValue(value);
    container.appendChild(row);
  }
}

function createInfoLine(className: string, label: string, value: string): HTMLParagraphElement {
  const line = document.createElement('p');
  line.className = className;

  const labelElement = document.createElement('span');
  labelElement.className = 'image-row-field-label';
  labelElement.textContent = `${label}: `;

  line.append(labelElement, value);
  return line;
}

async function giveMissingItem(itemName: string, button: HTMLButtonElement): Promise<void> {
  button.disabled = true;
  button.classList.add('is-pending');
  setStatus(`Preparing ${itemName}...`, 'info');

  try {
    const response = await nui<GiveItemResponse>('giveItem', { item: itemName });

    if (!response.ok) {
      setStatus(response.error ?? 'Failed to give item.', 'error');
      return;
    }

    setStatus(response.message ?? 'Item added.', 'success');
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error.';
    setStatus(message, 'error');
  } finally {
    button.disabled = false;
    button.classList.remove('is-pending');
  }
}

function renderMissingItems(items: MissingItem[], emptyMessage = 'No missing images.'): void {
  if (!missingList) return;

  missingList.innerHTML = '';

  if (items.length === 0) {
    missingList.appendChild(createEmptyRow(emptyMessage));
    return;
  }

  for (const entry of items) {
    const row = document.createElement('div');
    row.className = 'result-row image-result-row';

    const text = document.createElement('div');
    text.className = 'image-row-text';

    const imageText = entry.item === entry.image
      ? (entry.imageFile ?? `${entry.image}.png`)
      : `${entry.imageFile ?? `${entry.image}.png`} expected`;
    const item = createInfoLine('image-row-title', 'Name', entry.item);
    const label = entry.label ? createInfoLine('image-row-label', 'Label', entry.label) : null;
    const image = createInfoLine('image-row-meta', 'Image', imageText);

    const button = document.createElement('button');
    button.type = 'button';
    button.title = 'Give yourself this item';
    button.setAttribute('aria-label', `Give yourself ${entry.item}`);
    button.className = 'image-give-button';

    const buttonIcon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    buttonIcon.setAttribute('viewBox', '0 0 640 640');
    buttonIcon.setAttribute('aria-hidden', 'true');
    buttonIcon.setAttribute('focusable', 'false');
    buttonIcon.classList.add('image-give-icon');

    const buttonIconPath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    buttonIconPath.setAttribute('d', 'M352 128C352 110.3 337.7 96 320 96C302.3 96 288 110.3 288 128L288 288L128 288C110.3 288 96 302.3 96 320C96 337.7 110.3 352 128 352L288 352L288 512C288 529.7 302.3 544 320 544C337.7 544 352 529.7 352 512L352 352L512 352C529.7 352 544 337.7 544 320C544 302.3 529.7 288 512 288L352 288L352 128z');
    buttonIcon.appendChild(buttonIconPath);

    const tooltip = document.createElement('span');
    tooltip.className = 'image-tooltip';
    tooltip.textContent = 'Give yourself this item';

    button.append(buttonIcon, tooltip);
    button.addEventListener('click', () => {
      void giveMissingItem(entry.item, button);
    });

    text.append(item);

    if (label) {
      text.appendChild(label);
    }

    text.appendChild(image);
    row.append(text, button);
    missingList.appendChild(row);
  }
}

function renderUnusedImages(report: ScanReport, imagesOverride?: UnusedImage[], emptyMessage = 'No unused images.'): void {
  if (!unusedList) return;

  unusedList.innerHTML = '';

  if (!report.reportUnusedImages) {
    unusedList.appendChild(createEmptyRow('Disabled in config.'));
    return;
  }

  const images: UnusedImage[] = imagesOverride ?? report.unusedImageEntries ?? report.unusedImages.map((name): UnusedImage => ({
    name,
    fileName: name,
  }));

  if (images.length === 0) {
    unusedList.appendChild(createEmptyRow(emptyMessage));
    return;
  }

  for (const image of images) {
    const row = document.createElement('div');
    row.className = 'result-row image-result-row image-result-row-tall';

    const preview = document.createElement('div');
    preview.className = 'image-preview';

    if (image.url) {
      const img = document.createElement('img');
      img.src = image.url;
      img.alt = image.fileName;
      img.className = 'image-preview-img';
      img.onerror = () => {
        preview.textContent = '?';
        preview.classList.add('image-preview-empty');
      };
      preview.appendChild(img);
    } else {
      preview.textContent = '?';
      preview.classList.add('image-preview-empty');
    }

    const text = document.createElement('div');
    text.className = 'image-row-text';

    const name = document.createElement('p');
    name.className = 'image-row-title';
    name.textContent = image.fileName;

    const detail = document.createElement('p');
    detail.className = 'image-row-meta';
    detail.textContent = image.name;

    text.append(name, detail);
    row.append(preview, text);
    unusedList.appendChild(row);
  }
}

function renderFilteredLists(): void {
  if (!currentReport) return;

  const missingQuery = getSearchQuery(missingSearch);
  const unusedQuery = getSearchQuery(unusedSearch);

  const filteredMissing = currentReport.missingItems.filter((entry) => matchesMissingItem(entry, missingQuery));
  const unusedImages: UnusedImage[] = currentReport.unusedImageEntries ?? currentReport.unusedImages.map((name): UnusedImage => ({
    name,
    fileName: name,
  }));
  const filteredUnused = unusedImages.filter((entry) => matchesUnusedImage(entry, unusedQuery));

  renderMissingItems(
    filteredMissing,
    currentReport.missingItems.length === 0 ? 'No missing images.' : 'No results.',
  );

  renderUnusedImages(
    currentReport,
    filteredUnused,
    unusedImages.length === 0 ? 'No unused images.' : 'No results.',
  );
}

function hideScanState(): void {
  scanState?.classList.add('hidden');

  if (scanState) {
    scanState.innerHTML = '';
  }
}

function hideImageWorkspace(): void {
  imageWorkspace?.classList.add('hidden');
}

function showImageWorkspace(): void {
  imageWorkspace?.classList.remove('hidden');
}

function clearResultLists(): void {
  if (missingList) missingList.innerHTML = '';
  if (unusedList) unusedList.innerHTML = '';
}

function renderScanningState(): void {
  hideImageWorkspace();

  if (scanState) {
    scanState.innerHTML = '';
    scanState.appendChild(createScanningRow());
    scanState.classList.remove('hidden');
  }

  startScanningMessages();
}

function renderInitialState(): void {
  currentReport = null;
  isScanning = false;
  cancelRequested = false;
  stopScanningMessages();

  if (missingSearch) missingSearch.value = '';
  if (unusedSearch) unusedSearch.value = '';

  setStats(0, 0);
  hideStats();
  clearResultLists();
  hideImageWorkspace();
  hideScanState();
  resetProgress();
  clearStatus();
}

function renderReport(report: ScanReport): void {
  const unusedImages: UnusedImage[] = report.unusedImageEntries ?? report.unusedImages.map((name): UnusedImage => ({
    name,
    fileName: name,
  }));
  currentReport = report;

  setStats(report.missingItems.length, unusedImages.length);
  showStats();

  hideScanState();
  showImageWorkspace();
  renderFilteredLists();
}

async function runScan(): Promise<void> {
  isScanning = true;
  cancelRequested = false;
  setLoading(true);
  clearStatus();
  resetProgress();
  setStats(0, 0);
  showStats();
  renderScanningState();
  scanStartedAt = Date.now();
  renderScanProgress({
    phase: 'running',
    scannedRoots: 0,
    totalRoots: 1,
    scannedPaths: 0,
  });

  try {
    const response = await nui<NuiResponse>('scan');

    if (!response.ok) {
      hideScanState();

      if (currentReport) {
        const unusedImages: UnusedImage[] = currentReport.unusedImageEntries ?? currentReport.unusedImages.map((name): UnusedImage => ({
          name,
          fileName: name,
        }));
        setStats(currentReport.missingItems.length, unusedImages.length);
        showStats();
        showImageWorkspace();
        renderFilteredLists();
      } else {
        hideStats();
        hideImageWorkspace();
      }

      setStatus(response.error ?? 'Scan failed.', 'error');
      return;
    }

    renderReport(response.report);
    renderScanProgress({
      phase: response.report.canceled ? 'canceled' : 'complete',
      scannedRoots: response.report.scannedRoots ?? 1,
      totalRoots: response.report.totalRoots ?? response.report.scannedRoots ?? 1,
      scannedPaths: response.report.scannedPaths ?? response.report.imageCount,
      missingItems: response.report.missingItems.length,
      unusedImages: (response.report.unusedImageEntries ?? response.report.unusedImages).length,
    });
  } catch (error) {
    hideScanState();

    if (currentReport) {
      const unusedImages: UnusedImage[] = currentReport.unusedImageEntries ?? currentReport.unusedImages.map((name): UnusedImage => ({
        name,
        fileName: name,
      }));
      setStats(currentReport.missingItems.length, unusedImages.length);
      showStats();
      showImageWorkspace();
      renderFilteredLists();
    } else {
      hideStats();
      hideImageWorkspace();
    }

    const message = error instanceof Error ? error.message : 'Unknown error.';
    setStatus(message, 'error');
  } finally {
    stopScanningMessages();
    isScanning = false;
    cancelRequested = false;
    setLoading(false);
  }
}

async function cancelScan(): Promise<void> {
  if (!isScanning || cancelRequested) return;

  cancelRequested = true;
  setLoading(true, true);

  try {
    const response = await nui<CancelScanResponse>('cancelScan');

    if (!isScanning) {
      return;
    }

    if (!response.ok) {
      cancelRequested = false;
      setLoading(true);
      setStatus(response.error ?? 'Scan could not be canceled.', 'error');
    }
  } catch (error) {
    if (!isScanning) {
      return;
    }

    cancelRequested = false;
    setLoading(true);
    const message = error instanceof Error ? error.message : 'Unknown error.';
    setStatus(message, 'error');
  }
}

async function closeUi(): Promise<void> {
  stopScanningMessages();
  document.body.classList.add('hidden');
  await nui('close');
}

window.addEventListener('message', (event: MessageEvent<{ action?: string; payload?: OpenPayload | ScanProgress }>) => {
  if (event.data.action === 'open') {
    document.body.classList.remove('hidden');

    if (isScanning) {
      clearStatus();
      setLoading(true, cancelRequested);
      renderScanningState();
      return;
    }

    renderInitialState();
  }

  if (event.data.action === 'close') {
    stopScanningMessages();
    document.body.classList.add('hidden');
  }

  if (event.data.action === 'scanProgress') {
    renderScanProgress((event.data.payload ?? {}) as ScanProgress);
  }
});

scanButton?.addEventListener('click', () => {
  if (isScanning) {
    void cancelScan();
    return;
  }

  void runScan();
});

missingSearch?.addEventListener('input', renderFilteredLists);

unusedSearch?.addEventListener('input', renderFilteredLists);

closeButton?.addEventListener('click', () => {
  void closeUi();
});

window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    void closeUi();
  }
});

void nui('ready').catch(() => undefined);
