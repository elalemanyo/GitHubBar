// GitHubBar site: renders the features as a GitHub pull request list, each with its own PR page,
// and fills in the latest release and star count from the GitHub API.

const REPO = "elalemanyo/GitHubBar";
const REPO_URL = `https://github.com/${REPO}`;
const AUTHOR = "elalemanyo";
const AVATAR = `https://github.com/${AUTHOR}.png?size=80`;

const COMMITS = {
  scaffold: "b247274158e5d5135000d9747bfc491091b4b5b5",
  actions: "6fd10cb440dc8909bcb7beeb493577d046dcc056",
  polish: "fa191619f207c8cdcee4c94144f6ccd9778a638d",
  sparkle: "bedb6407567e566ad5660fc502248abe27547550",
  reminders: "3d61887642cef9c4f1ce123f15c5af738bb11598",
  aiPrompt: "888c5f1b4181573b17b1e41cf1c5a8e93eeb9434",
};

const LABELS = {
  documentation: { color: "0075ca", description: "Improvements or additions to documentation" },
  feature: { color: "a2eeef", description: "Something new you can do" },
  notifications: { color: "0e8a16", description: "Your GitHub notifications inbox" },
  ui: { color: "d4c5f9", description: "Menu bar icon and popover" },
  keyboard: { color: "fbca04", description: "Shortcuts and keyboard navigation" },
  ai: { color: "8250df", description: "Works with your AI assistant" },
  updates: { color: "1d76db", description: "Releases and automatic updates" },
  security: { color: "b60205", description: "Privacy and security" },
  design: { color: "f9d0c4", description: "Primer, Octicons and the GitHub look" },
};

const icon = (name, extra = "") =>
  `<svg class="octicon ${extra}" aria-hidden="true"><use href="#octicon-${name}"></use></svg>`;

const kbd = (...keys) => keys.map((k) => `<kbd>${k}</kbd>`).join(" ");

// MARK: - Content

const GETTING_STARTED = {
  kind: "issue",
  number: 1,
  title: "Getting started with GitHubBar",
  labels: ["documentation"],
  body: `
    <p>Welcome! GitHubBar lives in your menu bar and keeps your GitHub notifications, pull requests and review requests one click away. Setup takes about two minutes.</p>
    <h3>1. Install</h3>
    <ol>
      <li><a data-download href="${REPO_URL}/releases/latest">Download the latest release</a> and drag <strong>GitHubBar</strong> to your Applications folder.</li>
      <li>Open it. GitHubBar isn't notarized by Apple, so macOS blocks the first launch: open <strong>System Settings → Privacy &amp; Security</strong> and click <strong>Open Anyway</strong>. You only do this once, updates install themselves.</li>
    </ol>
    <p>Prefer the Terminal? This does the same:</p>
    <pre><code>xattr -dr com.apple.quarantine /Applications/GitHubBar.app</code></pre>
    <h3>2. Add a token</h3>
    <p><a href="https://github.com/settings/tokens/new?scopes=repo,notifications&amp;description=GitHubBar">Create a classic personal access token</a> with the <code>repo</code> and <code>notifications</code> scopes, then paste it in GitHubBar's Settings. It's stored in your Keychain.</p>
    <blockquote><p>Fine-grained tokens work for search tabs, but GitHub doesn't let them read notifications.</p></blockquote>
    <h3>3. Make it yours</h3>
    <p>You start with three tabs: <strong>Inbox</strong>, <strong>Review requests</strong> and <strong>My pull requests</strong>. Add more from presets, or write your own query. The merged pull requests below show everything GitHubBar can do.</p>
  `,
};

const FEATURES = [
  {
    number: 2,
    title: "Tabs for anything you want to watch",
    labels: ["feature"],
    branch: "feature/tabs",
    commit: COMMITS.scaffold,
    version: "v0.0.1",
    body: `
      <p>Every tab is a title, an Octicon and a query. Start from a preset or write your own, then drag tabs into the order you like. <kbd>⌘</kbd> <kbd>1</kbd>–<kbd>9</kbd> jumps straight to them.</p>
      <h3>Search tabs</h3>
      <p>Search tabs use the same syntax as the search bar on github.com, so anything you can find there you can keep in your menu bar:</p>
      <pre><code>is:pr is:open review-requested:@me archived:false</code></pre>
      <p>All search tabs are fetched together in a single GraphQL request, and a bad query only breaks its own tab.</p>
      <h3>Presets</h3>
      <table>
        <thead><tr><th>Preset</th><th>Query</th></tr></thead>
        <tbody>
          <tr><td>Review requests</td><td><code>is:pr is:open review-requested:@me</code></td></tr>
          <tr><td>My pull requests</td><td><code>is:pr is:open author:@me</code></td></tr>
          <tr><td>Failing CI</td><td><code>is:pr is:open author:@me status:failure</code></td></tr>
          <tr><td>Ready to merge</td><td><code>is:pr is:open author:@me review:approved</code></td></tr>
          <tr><td>Assigned to me</td><td><code>is:open assignee:@me</code></td></tr>
          <tr><td>Mentioned</td><td><code>is:open mentions:@me</code></td></tr>
        </tbody>
      </table>
      <p>Plus notification presets like <strong>Inbox</strong>, <strong>Mentions</strong> and <strong>CI activity</strong>.</p>
    `,
  },
  {
    number: 3,
    title: "Notification tabs with filters",
    labels: ["feature", "notifications"],
    branch: "feature/notification-filters",
    commit: COMMITS.scaffold,
    version: "v0.0.1",
    body: `
      <p>Notification tabs filter your unread notifications with a small, search-like syntax:</p>
      <table>
        <thead><tr><th>Qualifier</th><th>Example</th></tr></thead>
        <tbody>
          <tr><td><code>reason:</code></td><td><code>reason:review_requested</code>, <code>reason:mention,team_mention</code></td></tr>
          <tr><td><code>type:</code></td><td><code>type:pr</code>, <code>type:Issue</code>, <code>type:Release</code>, <code>type:ci</code></td></tr>
          <tr><td><code>state:</code></td><td><code>state:open</code>, <code>-state:merged,closed</code></td></tr>
          <tr><td><code>repo:</code></td><td><code>repo:owner/name</code></td></tr>
          <tr><td><code>org:</code></td><td><code>org:owner</code></td></tr>
        </tbody>
      </table>
      <p>Commas mean "any of", a leading <code>-</code> excludes, and plain words match the title. Splitting your organizations from everything else takes two tabs:</p>
      <pre><code>org:acme,globex
-org:acme,globex</code></pre>
      <p>All notification tabs share one conditional request, so extra tabs don't cost anything against GitHub's rate limit.</p>
    `,
  },
  {
    number: 4,
    title: "The menu bar icon tells you when something needs you",
    labels: ["feature", "ui"],
    branch: "feature/attention",
    commit: COMMITS.polish,
    version: "v0.0.1",
    body: `
      <p>The cat in your menu bar turns <strong>GitHub blue</strong> when a tab needs your attention, in a lighter blue when your menu bar is dark.</p>
      <p>Each tab decides when that happens:</p>
      <ul>
        <li><strong>Never</strong>: for tabs you just want to glance at, like your own open pull requests.</li>
        <li><strong>When it has items</strong>: review requests, unread notifications.</li>
        <li><strong>When new items appear</strong>: only what showed up since you last looked.</li>
      </ul>
      <p>New items get a blue dot until you've seen them, and tab counters light up like GitHub's.</p>
    `,
  },
  {
    number: 5,
    title: "Mark notifications as read or done",
    labels: ["notifications"],
    branch: "feature/read-and-done",
    commit: COMMITS.actions,
    version: "v0.0.1",
    body: `
      <p>Triage your inbox without opening a browser:</p>
      <ul>
        <li>Hover a notification to mark it as <strong>read</strong> ${icon("eye")} or <strong>done</strong> ${icon("check")}.</li>
        <li>Clear a whole tab at once from the footer.</li>
        <li>Or use GitHub's own shortcuts: ${kbd("E")} for done, ${kbd("⇧", "I")} for read.</li>
      </ul>
      <p>Opening a notification marks it as read. <strong>Done</strong> also removes it from your github.com inbox, just like on the web. A filtered tab only clears what it shows, so "Mark all as done" on <em>Mentions</em> leaves the rest of your inbox alone.</p>
    `,
  },
  {
    number: 6,
    title: "Pull request state, checks and reviews at a glance",
    labels: ["feature"],
    branch: "feature/subject-state",
    commit: COMMITS.actions,
    version: "v0.0.1",
    body: `
      <p>Every row shows whether a pull request is open, draft, merged or closed in GitHub's colors, plus its CI status and review decision (<em>Approved</em>, <em>Changes requested</em>).</p>
      <p>Notification rows too: GitHub's notifications don't say what state a pull request is in, so GitHubBar looks it up in one batched request. That also powers filters like:</p>
      <pre><code>-state:merged,closed</code></pre>
      <p>to hide notifications for work that's already finished.</p>
    `,
  },
  {
    number: 7,
    title: "macOS notifications for new items",
    labels: ["feature", "notifications"],
    branch: "feature/system-notifications",
    commit: COMMITS.actions,
    version: "v0.0.1",
    body: `
      <p>Turn on <strong>Notify me about new items</strong> for any tab, say, <em>Review requests</em>, and get a macOS notification the moment something new arrives.</p>
      <ul>
        <li>Up to three items are shown individually, the rest as one summary.</li>
        <li>Clicking one opens it on GitHub, and marks GitHub notifications as read.</li>
        <li>Editing a tab's query never floods you with "new" items.</li>
      </ul>
    `,
  },
  {
    number: 8,
    title: "Keyboard shortcuts from GitHub's inbox",
    labels: ["keyboard"],
    branch: "feature/shortcuts",
    commit: COMMITS.actions,
    version: "v0.0.1",
    body: `
      <p>If you use GitHub's notification shortcuts, you already know these. Press ${kbd("?")} in the popover to see them all.</p>
      <table>
        <thead><tr><th>Keys</th><th>Action</th></tr></thead>
        <tbody>
          <tr><td>${kbd("⌘", "1")} – ${kbd("⌘", "9")}, ${kbd("←")} ${kbd("→")}</td><td>Switch tab</td></tr>
          <tr><td>${kbd("J")} ${kbd("K")}, ${kbd("↓")} ${kbd("↑")}</td><td>Next / previous item</td></tr>
          <tr><td>${kbd("O")}, ${kbd("↩")}</td><td>Open in browser</td></tr>
          <tr><td>${kbd("⌘", "↩")}, ${kbd("⌘")}-click</td><td>Open in a background tab</td></tr>
          <tr><td>${kbd("E")}</td><td>Mark as done</td></tr>
          <tr><td>${kbd("⇧", "I")}</td><td>Mark as read</td></tr>
          <tr><td>${kbd("⌘", "R")}</td><td>Refresh</td></tr>
          <tr><td>${kbd("Esc")}</td><td>Close</td></tr>
        </tbody>
      </table>
    `,
  },
  {
    number: 9,
    title: "Open GitHubBar from anywhere",
    labels: ["keyboard"],
    branch: "feature/global-shortcut",
    commit: COMMITS.actions,
    version: "v0.0.1",
    body: `
      <p>Pick a global shortcut in <strong>Settings → Account</strong> and GitHubBar opens from any app, keyboard focus ready for ${kbd("J")} ${kbd("K")}.</p>
      <p>There's no default, so it never collides with your other apps, and it doesn't need Accessibility permissions.</p>
    `,
  },
  {
    number: 10,
    title: "Snooze when you need to focus",
    labels: ["feature", "ui"],
    branch: "feature/snooze",
    commit: COMMITS.actions,
    version: "v0.0.1",
    body: `
      <p>Deep in something? <strong>Snooze Highlighting</strong> in the gear menu keeps the menu bar icon quiet for an hour, four hours or until tomorrow morning.</p>
      <p>GitHubBar keeps refreshing in the background, so everything is up to date when you're back, but no highlight and no notifications until then. Click "Snoozed until…" in the footer to resume early.</p>
    `,
  },
  {
    number: 11,
    title: "Let your AI assistant write the query",
    labels: ["feature", "ai"],
    branch: "feature/ai-prompt",
    commit: COMMITS.aiPrompt,
    version: "v0.0.3",
    body: `
      <p>Don't remember whether it's <code>review-requested:</code> or <code>reason:review_requested</code>? Click <strong>Copy AI Prompt</strong> in the tab editor.</p>
      <p>The prompt contains the complete syntax for that tab, search or notifications, and its current query. Paste it into Claude, ChatGPT or any assistant, describe what you want in your own words, and paste the one-line answer back:</p>
      <blockquote><p>"Pull requests in my company's repos that are waiting for my review, but not drafts."</p></blockquote>
      <p><strong>Test Query</strong> then shows how many items match before you save.</p>
    `,
  },
  {
    number: 12,
    title: "Export and import tabs",
    labels: ["feature"],
    branch: "feature/tab-export",
    commit: COMMITS.actions,
    version: "v0.0.1",
    body: `
      <p>Export your tabs as a JSON file and share the setup with your team, or move it to another Mac. Importing adds the tabs next to your existing ones.</p>
      <pre><code>{
  "title": "Review requests",
  "icon": "code-review",
  "source": "search",
  "query": "is:pr is:open review-requested:@me",
  "attention": "anyItems"
}</code></pre>
    `,
  },
  {
    number: 13,
    title: "Automatic updates",
    labels: ["updates"],
    branch: "feature/sparkle",
    commit: COMMITS.sparkle,
    version: "v0.0.1",
    body: `
      <p>GitHubBar updates itself with <a href="https://sparkle-project.org">Sparkle</a>. Every release is signed, and the app only installs updates carrying that signature.</p>
      <p>Instead of interrupting you with a window, a new version shows up as a small banner in the popover and a dot on the gear. Install when it suits you, or let GitHubBar install updates automatically.</p>
    `,
  },
  {
    number: 14,
    title: "Private by design",
    labels: ["security"],
    branch: "feature/privacy",
    commit: COMMITS.scaffold,
    version: "v0.0.1",
    body: `
      <ul>
        <li>Your token is stored in the macOS <strong>Keychain</strong>.</li>
        <li>The app runs in the macOS <strong>sandbox</strong>: it can reach the network and files you pick, nothing else on your Mac.</li>
        <li>It only talks to <code>api.github.com</code>. No analytics, no accounts, no servers of its own.</li>
        <li>It's <a href="${REPO_URL}">open source</a>, so you can read exactly what it does.</li>
      </ul>
    `,
  },
  {
    number: 15,
    title: "Looks and feels like GitHub",
    labels: ["design"],
    branch: "feature/primer",
    commit: COMMITS.scaffold,
    version: "v0.0.1",
    body: `
      <p>GitHubBar is built with GitHub's own design system, <a href="https://primer.style">Primer</a>: its color tokens for light and dark mode, Octicons, the underline tab bar, counters and labels.</p>
      <p>It feels like a small piece of GitHub that lives in your menu bar, and so does this page.</p>
    `,
  },
];

// MARK: - Helpers

function labelStyle(name) {
  const hex = LABELS[name]?.color ?? "8b949e";
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  const text = luminance > 0.6 ? "#1f2328" : "#ffffff";
  return `--label-r:${r};--label-g:${g};--label-b:${b};--label-text:${text}`;
}

const labelHTML = (name) =>
  `<span class="IssueLabel" style="${labelStyle(name)}" data-label="${name}" title="${LABELS[name]?.description ?? ""}">${name}</span>`;

const plainText = (html) => html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").toLowerCase();

function storage(fn) {
  try {
    return fn(window.sessionStorage);
  } catch {
    return null;
  }
}

// MARK: - List

const listEl = document.querySelector("[data-list]");
const searchEl = document.querySelector("[data-search]");
const featuresEl = document.querySelector(".Features");
const detailEl = document.querySelector("[data-detail]");

function matches(feature, query) {
  const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
  const text = `${feature.title} ${plainText(feature.body)} ${feature.labels.join(" ")}`.toLowerCase();
  return terms.every((term) => {
    if (term === "is:pr" || term === "is:merged" || term === "is:closed") return true;
    if (term === "is:open" || term === "is:issue") return false;
    if (term.startsWith("label:")) {
      return term.slice(6).split(",").some((l) => feature.labels.includes(l));
    }
    if (term.startsWith("-label:")) {
      return !term.slice(7).split(",").some((l) => feature.labels.includes(l));
    }
    return text.includes(term);
  });
}

function renderList() {
  const query = searchEl.value;
  const visible = FEATURES.filter((f) => matches(f, query));
  document.querySelector("[data-merged-count]").textContent = visible.length;

  if (visible.length === 0) {
    listEl.innerHTML = `<div class="Row-empty">No results matched your search.</div>`;
    return;
  }

  listEl.innerHTML = visible
    .map(
      (f) => `
      <div class="Row">
        ${icon("git-merge")}
        <div class="Row-main">
          <a class="Row-link" href="#pull/${f.number}">${f.title}</a>
          <span class="Row-labels">${f.labels.map(labelHTML).join("")}</span>
          <div class="Row-meta">#${f.number} by ${AUTHOR} was merged in ${f.version} ${icon("check")}</div>
        </div>
      </div>`
    )
    .join("");
}

function toggleLabel(name) {
  const term = `label:${name}`;
  const terms = searchEl.value.split(/\s+/).filter(Boolean);
  const next = terms.includes(term) ? terms.filter((t) => t !== term) : [...terms, term];
  searchEl.value = `${next.join(" ")} `;
  renderList();
}

function renderLabelMenu() {
  document.querySelector("[data-label-menu]").innerHTML = Object.entries(LABELS)
    .filter(([name]) => name !== "documentation")
    .map(
      ([name, { description }]) => `
      <button class="LabelMenu-item" type="button" data-label="${name}" style="${labelStyle(name)}">
        <span class="swatch"></span>
        <span>${name}<small>${description}</small></span>
      </button>`
    )
    .join("");
}

searchEl.addEventListener("input", renderList);

document.addEventListener("click", (event) => {
  const label = event.target.closest("[data-label]");
  if (!label || !(label.dataset.label in LABELS) || label.dataset.label === "documentation") return;
  event.preventDefault();
  label.closest("details")?.removeAttribute("open");
  if (location.hash.startsWith("#pull") || location.hash.startsWith("#issue")) {
    history.pushState(null, "", "#features");
    route();
  }
  toggleLabel(label.dataset.label);
});

// MARK: - Pull request page

function timelineEvent(badgeIcon, html, modifier = "") {
  return `
    <div class="Event">
      <span class="Event-badge ${modifier}">${icon(badgeIcon)}</span>
      <span>${html}</span>
    </div>`;
}

function renderDetail(item) {
  const isIssue = item.kind === "issue";
  const sha = item.commit?.slice(0, 7);

  const state = isIssue
    ? `<span class="State State--open">${icon("issue-opened")} Open</span>
       <span><strong>${AUTHOR}</strong> opened this issue · pinned</span>`
    : `<span class="State">${icon("git-merge")} Merged</span>
       <span><strong>${AUTHOR}</strong> merged commits into <span class="BranchName">main</span> from <span class="BranchName">${item.branch}</span></span>`;

  const tabs = isIssue
    ? `<span aria-current="page">${icon("comment")} Conversation</span>`
    : `<span aria-current="page">${icon("comment")} Conversation</span>
       <span>${icon("git-commit")} Commits</span>
       <span>${icon("checklist")} Checks</span>
       <span>${icon("file-diff")} Files changed</span>`;

  const events = isIssue
    ? timelineEvent("pin", `<strong>${AUTHOR}</strong> pinned this issue`) +
      timelineEvent("tag", `<strong>${AUTHOR}</strong> added the ${item.labels.map(labelHTML).join("")} label`)
    : timelineEvent("tag", `<strong>${AUTHOR}</strong> added the ${item.labels.map(labelHTML).join("")} label${item.labels.length > 1 ? "s" : ""}`) +
      timelineEvent("check", `All checks have passed`, "Event-badge--success") +
      timelineEvent(
        "git-merge",
        `<strong>${AUTHOR}</strong> merged commit <a href="${REPO_URL}/commit/${item.commit}"><code>${sha}</code></a> into <span class="BranchName">main</span>`,
        "Event-badge--done"
      ) +
      timelineEvent("package", `Released in <a href="${REPO_URL}/releases/tag/${item.version}"><strong>${item.version}</strong></a>`);

  const sidebar = `
    <aside class="Sidebar">
      ${isIssue ? "" : `
      <section>
        <h3>Reviewers</h3>
        <div class="person"><img src="${AVATAR}" alt="">${AUTHOR}${icon("check")}</div>
      </section>`}
      <section>
        <h3>Assignees</h3>
        <div class="person"><img src="${AVATAR}" alt="">${AUTHOR}</div>
      </section>
      <section>
        <h3>Labels</h3>
        ${item.labels.map(labelHTML).join("")}
      </section>
      ${isIssue ? "" : `
      <section>
        <h3>Milestone</h3>
        ${icon("milestone")} <a href="${REPO_URL}/releases/tag/${item.version}">${item.version}</a>
      </section>`}
    </aside>`;

  detailEl.innerHTML = `
    <a class="Back" href="#features">${icon("arrow-left")} All features</a>
    <h2 class="Detail-title">${item.title} <span class="number">#${item.number}</span></h2>
    <div class="Detail-state">${state}</div>
    <nav class="UnderlineNav" aria-label="Pull request tabs">${tabs}</nav>
    <div class="Detail-layout">
      <div class="Timeline">
        <div class="Comment">
          <img class="Comment-avatar" src="${AVATAR}" alt="">
          <div class="Comment-box">
            <div class="Comment-header">
              <strong>${AUTHOR}</strong> ${isIssue ? "opened this issue" : "commented"}
              <span class="role">Owner</span>
            </div>
            <div class="markdown-body">${item.body}</div>
          </div>
        </div>
        <div class="Events">${events}</div>
      </div>
      ${sidebar}
    </div>`;

  applyRelease();
}

// MARK: - Routing

function route() {
  const match = location.hash.match(/^#(pull|issue)\/(\d+)$/);
  const number = match && Number(match[2]);
  const item = match?.[1] === "issue"
    ? (number === GETTING_STARTED.number ? GETTING_STARTED : null)
    : FEATURES.find((f) => f.number === number);

  if (item) {
    renderDetail(item);
    featuresEl.hidden = true;
    detailEl.hidden = false;
    document.title = `${item.title} · GitHubBar`;
    document.getElementById("features").scrollIntoView();
  } else {
    featuresEl.hidden = false;
    detailEl.hidden = true;
    document.title = "GitHubBar · Your GitHub inbox in the macOS menu bar";
    if (location.hash === "#features") document.getElementById("features").scrollIntoView();
  }
}

window.addEventListener("hashchange", route);

// MARK: - Latest release & stars

let release = null;

function applyRelease() {
  if (!release) return;
  document.querySelectorAll("[data-version]").forEach((el) => (el.textContent = release.version));
  document.querySelectorAll("[data-download]").forEach((el) => (el.href = release.download));
  document.querySelectorAll("[data-release-link]").forEach((el) => (el.href = release.url));
  const date = document.querySelector("[data-release-date]");
  if (date && release.date) {
    date.textContent = new Date(release.date).toLocaleDateString("en", { year: "numeric", month: "long", day: "numeric" });
  }
}

async function loadJSON(key, url) {
  const cached = storage((s) => s.getItem(key));
  if (cached) return JSON.parse(cached);
  const response = await fetch(url, { headers: { Accept: "application/vnd.github+json" } });
  if (!response.ok) throw new Error(response.statusText);
  const json = await response.json();
  storage((s) => s.setItem(key, JSON.stringify(json)));
  return json;
}

async function loadRelease() {
  try {
    const json = await loadJSON("ghb-release", `https://api.github.com/repos/${REPO}/releases/latest`);
    const dmg = json.assets?.find((a) => a.name.endsWith(".dmg"));
    release = {
      version: json.tag_name,
      date: json.published_at,
      url: json.html_url,
      download: dmg?.browser_download_url ?? `${REPO_URL}/releases/latest`,
    };
    applyRelease();
  } catch {
    // Keep the static fallback: "v0.0.3" and a link to the latest release page.
  }
}

async function loadStars() {
  try {
    const json = await loadJSON("ghb-repo", `https://api.github.com/repos/${REPO}`);
    const counter = document.querySelector("[data-stars]");
    counter.textContent = json.stargazers_count.toLocaleString("en");
    counter.hidden = false;
  } catch {
    // The Star button still works without a count.
  }
}

// MARK: - Start

renderLabelMenu();
renderList();
route();
loadRelease();
loadStars();
