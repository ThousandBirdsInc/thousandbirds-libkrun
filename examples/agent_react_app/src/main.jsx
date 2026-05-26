import React from "react";
import { createRoot } from "react-dom/client";
import "./style.css";

function App() {
  const tasks = [
    "Inspect this React app",
    "Edit components from inside Debian",
    "Run npm build or tests",
    "Use headless Chromium for browser checks",
  ];

  return (
    <main className="shell">
      <section className="panel">
        <p className="eyebrow">libkrun OS-mode agent workspace</p>
        <h1>React app mounted into a Debian VM</h1>
        <p className="summary">
          This app is intentionally small so an AI coding agent can edit it,
          run normal Node tooling, and verify browser output from the guest.
        </p>
        <ul>
          {tasks.map((task) => (
            <li key={task}>{task}</li>
          ))}
        </ul>
      </section>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
