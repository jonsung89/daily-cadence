const NoteEditor = ({ onClose, onSave }) => {
  const [type, setType] = useState("meal");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const types = ["workout","meal","sleep","mood","activity"];

  return (
    <>
      <TopBar
        sub="New note · now"
        title="What's on your mind?"
        left={<button className="iconbtn" onClick={onClose}><Icon name="x" /></button>}
      />
      <div className="content">
        <div className="section-label">Type</div>
        <div className="type-row">
          {types.map(t => {
            const c = TYPE_COLORS[t];
            const active = type === t;
            return (
              <button key={t} className={"type-chip" + (active ? " active" : "")} onClick={() => setType(t)}>
                <span className="ic" style={{ background: active ? "color-mix(in oklch, var(--bg-1) 10%, transparent)" : c.soft }}>
                  <Icon name={c.icon} size={20} color={active ? "var(--bg-1)" : c.dot} />
                </span>
                <span className="lbl">{c.label}</span>
              </button>
            );
          })}
        </div>

        <div className="section-label">Title</div>
        <input
          value={title}
          onChange={e => setTitle(e.target.value)}
          placeholder={TYPE_COLORS[type].label === "Meal" ? "Oatmeal, berries…" : "A short title"}
          style={{
            width: "100%", padding: "14px 16px", border: "1px solid var(--border-1)",
            borderRadius: 10, background: "var(--bg-2)", fontSize: 16, fontFamily: "var(--font-sans)",
            color: "var(--dc-ink)", boxSizing: "border-box", outline: "none"
          }}
        />

        <div className="section-label">Note</div>
        <textarea
          value={body}
          onChange={e => setBody(e.target.value)}
          rows={4}
          placeholder="Anything to remember about this moment…"
          style={{
            width: "100%", padding: "14px 16px", border: "1px solid var(--border-1)",
            borderRadius: 10, background: "var(--bg-2)", fontSize: 15, fontFamily: "var(--font-sans)",
            color: "var(--dc-ink)", boxSizing: "border-box", resize: "none", outline: "none", lineHeight: 1.5
          }}
        />

        <div style={{ display: "flex", gap: 10, marginTop: 22 }}>
          <button onClick={onClose} style={{
            flex: 1, padding: "14px", borderRadius: 10, border: "1px solid var(--border-1)",
            background: "var(--bg-2)", fontSize: 15, fontWeight: 500, color: "var(--fg-1)", cursor: "pointer"
          }}>Cancel</button>
          <button onClick={onSave} style={{
            flex: 2, padding: "14px", borderRadius: 10, border: 0,
            background: "var(--dc-sage)", color: "var(--fg-on-accent)", fontSize: 15, fontWeight: 600, cursor: "pointer"
          }}>Save to today</button>
        </div>
      </div>
    </>
  );
};

window.NoteEditor = NoteEditor;
