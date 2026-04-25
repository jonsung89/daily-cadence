const Timeline = ({ onOpenEditor }) => {
  const [view, setView] = useState("timeline");
  const [dragId, setDragId] = useState(null);
  const [order, setOrder] = useState([0,1,2,3,4,5,6,7,8,9,10]);

  // Timeline items (chronological)
  const tlItems = [
    { time: "6:45",  type: "sleep",    title: "Slept 7h 20m",       body: "Solid. Woke up once around 3am." },
    { time: "7:12",  type: "workout",  title: "Easy run · 35 min",  body: "Felt strong. Legs tight early on." },
    { time: "8:30",  type: "meal",     title: "Breakfast",          body: "Oatmeal, blueberries, coffee." },
    { time: "10:05", type: "mood",     title: "Focused",            body: "Clear head. Deep work morning." },
    { time: "12:40", type: "meal",     title: "Lunch",              body: "Grain bowl, salmon, greens." },
    { time: "3:15",  type: "activity", title: "Walk · 2.3 mi",      body: "Park loop with a podcast." },
  ];

  // Keep-style cards — genuinely varied heights, mixed shapes (titles, bodies, checklists, just-text, color-tinted backgrounds)
  // Order matters — masonry flows top-to-bottom per column, so we assign to columns explicitly to get the staggered Keep look
  const keepItems = [
    // Col 0
    { type: "mood",     kind: "title",  title: "Focused",                                                           col: 0 },
    { type: "workout",  kind: "body",   title: "Easy run · 35 min", body: "Felt strong. Legs tight early on. Sunrise over the reservoir, cool air.", col: 0 },
    { type: "meal",     kind: "list",   title: "Breakfast",  items: ["Oatmeal", "Blueberries", "Coffee"],           col: 0 },
    { type: "activity", kind: "title",  title: "Walk · 2.3 mi",                                                     col: 0 },
    { type: "mood",     kind: "body",   title: "Wound down easy", body: "Read a few chapters. Early bedtime.",      col: 0 },

    // Col 1
    { type: "sleep",    kind: "stat",   title: "Slept",     stat: "7h 20m", sub: "Woke once around 3am",            col: 1 },
    { type: "meal",     kind: "body",   title: "Lunch",     body: "Grain bowl, salmon, greens, tahini.",            col: 1 },
    { type: "workout",  kind: "list",   title: "Stretch",   items: ["Hips", "Hamstrings", "Calves"],                col: 1 },
    { type: "mood",     kind: "quote",  body: "Noticed I'm less anxious on running days.",                          col: 1 },
    { type: "meal",     kind: "title",  title: "Tea · 3pm",                                                         col: 1 },
    { type: "activity", kind: "body",   title: "Evening stroll", body: "Half hour after dinner. Cool breeze.",      col: 1 },
  ];

  // Long-press to enter reorder mode
  const pressTimer = React.useRef(null);
  const startPress = (id) => { pressTimer.current = setTimeout(() => setDragId(id), 380); };
  const cancelPress = () => { if (pressTimer.current) clearTimeout(pressTimer.current); };
  const onDrop = (targetId) => {
    if (dragId === null || dragId === targetId) { setDragId(null); return; }
    const next = order.slice();
    const from = next.indexOf(dragId), to = next.indexOf(targetId);
    next.splice(to, 0, next.splice(from, 1)[0]);
    setOrder(next); setDragId(null);
  };

  const KeepCard = ({ idx }) => {
    const n = keepItems[idx];
    const t = TYPE_COLORS[n.type];
    const active = dragId === idx;
    return (
      <div
        className={"keep" + (active ? " drag" : "")}
        style={{ background: t.soft + "55", borderColor: t.dot + "33" }}
        onMouseDown={() => startPress(idx)}
        onTouchStart={() => startPress(idx)}
        onMouseUp={cancelPress}
        onMouseLeave={cancelPress}
        onTouchEnd={cancelPress}
        onClick={() => dragId !== null && onDrop(idx)}
      >
        <div className="keep-head">
          <span className="dot" style={{ background: t.dot }}></span>
          <span className="lbl" style={{ color: t.text }}>{t.label}</span>
        </div>
        {n.kind === "title" && <div className="keep-title">{n.title}</div>}
        {n.kind === "body" && (<>
          <div className="keep-title">{n.title}</div>
          <div className="keep-body">{n.body}</div>
        </>)}
        {n.kind === "stat" && (<>
          <div className="keep-title">{n.title}</div>
          <div className="keep-stat">{n.stat}</div>
          <div className="keep-body">{n.sub}</div>
        </>)}
        {n.kind === "list" && (<>
          <div className="keep-title">{n.title}</div>
          <ul className="keep-list">
            {n.items.map((it, i) => <li key={i}><span className="tick" /> {it}</li>)}
          </ul>
        </>)}
        {n.kind === "quote" && (<div className="keep-quote">"{n.body}"</div>)}
      </div>
    );
  };

  const col0 = order.filter(i => keepItems[i].col === 0);
  const col1 = order.filter(i => keepItems[i].col === 1);

  return (
    <>
      <TopBar sub="Thursday · April 23" title="A quiet day"
        right={<button className="iconbtn"><Icon name="search" /></button>} />

      <div style={{padding: "0 20px 12px"}}>
        <div className="segmented">
          <button className={"seg" + (view === "timeline" ? " on" : "")} onClick={() => setView("timeline")}>
            <Icon name="list" size={14} /> Timeline
          </button>
          <button className={"seg" + (view === "grid" ? " on" : "")} onClick={() => setView("grid")}>
            <Icon name="layout-grid" size={14} /> Cards
          </button>
        </div>
      </div>

      <div className="content">
        {view === "timeline" ? (
          <div className="timeline">
            {tlItems.map((it, i) => <TimelineItem key={i} {...it} />)}
          </div>
        ) : (
          <>
            {dragId !== null && (
              <div className="drag-hint"><Icon name="move" size={14} /> Tap a card to drop here</div>
            )}
            <div className="keep-grid">
              <div className="keep-col">
                {col0.map(idx => <KeepCard key={idx} idx={idx} />)}
              </div>
              <div className="keep-col">
                {col1.map(idx => <KeepCard key={idx} idx={idx} />)}
              </div>
            </div>
          </>
        )}
      </div>
      <button className="fab" onClick={onOpenEditor} aria-label="Add note">
        <Icon name="plus" size={26} color="var(--fg-on-accent)" strokeWidth={2} />
      </button>
    </>
  );
};

window.Timeline = Timeline;
