"use client";

export function WorkbenchTopBar({ onToggleAi }: { onToggleAi: () => void }) {
  return (
    <header
      className="border-b px-3"
      style={{
        background: "var(--panel-bg)",
        borderColor: "var(--border-color)",
      }}
    >
      <div className="flex h-10 items-center gap-3 text-[12px]">
        <div
          className="flex shrink-0 items-center gap-3"
          style={{ color: "var(--text-secondary)" }}
        >
          <span className="font-medium" style={{ color: "var(--text-main)" }}>
            AnySim
          </span>
          <button>文件</button>
          <button>编辑</button>
          <button>视图</button>
          <button>运行</button>
          <button>扩展</button>
          <button>帮助</button>
        </div>

        <div className="flex flex-1 justify-center px-3">
          <div
            className="flex h-7 w-full max-w-[50%] items-center border px-3 text-[11px]"
            style={{
              borderColor: "var(--border-color)",
              background: "var(--workspace-bg)",
              color: "var(--text-secondary)",
            }}
          >
            <SearchIcon />
            <span className="ml-2 truncate">
              搜索文件、命令、符号、组件、扩展...
            </span>
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-1">
          <button
            onClick={onToggleAi}
            className="flex h-7 w-7 items-center justify-center border"
            style={{
              borderColor: "var(--border-color)",
              color: "var(--text-secondary)",
              background: "var(--panel-subtle)",
            }}
            title="AI"
          >
            <AiIcon />
          </button>
          <button
            className="flex h-7 w-7 items-center justify-center border"
            style={{
              borderColor: "var(--border-color)",
              color: "var(--text-secondary)",
              background: "var(--panel-subtle)",
            }}
            title="Settings"
          >
            <SettingsIcon />
          </button>
        </div>
      </div>
    </header>
  );
}

function SearchIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </svg>
  );
}

function AiIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M12 3v3" />
      <path d="M12 18v3" />
      <path d="M5 12h3" />
      <path d="M16 12h3" />
      <rect x="8" y="8" width="8" height="8" rx="1.5" />
    </svg>
  );
}

function SettingsIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="3.5" />
      <path d="M19.4 15a1 1 0 0 0 .2 1.1l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1 1 0 0 0-1.1-.2 1 1 0 0 0-.6.9V20a2 2 0 1 1-4 0v-.2a1 1 0 0 0-.6-.9 1 1 0 0 0-1.1.2l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1 1 0 0 0 .2-1.1 1 1 0 0 0-.9-.6H4a2 2 0 1 1 0-4h.2a1 1 0 0 0 .9-.6 1 1 0 0 0-.2-1.1l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1 1 0 0 0 1.1.2 1 1 0 0 0 .6-.9V4a2 2 0 1 1 4 0v.2a1 1 0 0 0 .6.9 1 1 0 0 0 1.1-.2l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1 1 0 0 0-.2 1.1 1 1 0 0 0 .9.6H20a2 2 0 1 1 0 4h-.2a1 1 0 0 0-.9.6Z" />
    </svg>
  );
}
