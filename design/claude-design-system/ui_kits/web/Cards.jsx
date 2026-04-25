const Cards = () => {
  const [dragId, setDragId] = React.useState(null);
  const [hoverId, setHoverId] = React.useState(null);
  const [order, setOrder] = React.useState([0,1,2,3,4,5,6,7,8,9,10,11,12,13]);
  const [pinned, setPinned] = React.useState(new Set([0, 5]));
  const [search, setSearch] = React.useState("");

  // Desktop Keep: more columns, richer cards, bigger canvas
  const items = [
    { type: "mood",     kind: "title",  title: "Focused" },
    { type: "workout",  kind: "body",   title: "Easy run · 35 min", body: "Felt strong. Legs tight early on. Sunrise over the reservoir, cool air. Could have gone longer — save it for Saturday." },
    { type: "sleep",    kind: "stat",   title: "Slept",  stat: "7h 20m", sub: "Woke once around 3am" },
    { type: "meal",     kind: "list",   title: "Breakfast", items: ["Oatmeal", "Blueberries", "Coffee", "Almond butter"] },
    { type: "activity", kind: "title",  title: "Walk · 2.3 mi" },
    { type: "mood",     kind: "quote",  body: "Noticed I'm less anxious on running days." },
    { type: "meal",     kind: "body",   title: "Lunch", body: "Grain bowl with salmon, roasted greens, tahini dressing. Filling, didn't crash at 3." },
    { type: "workout",  kind: "list",   title: "Stretch routine", items: ["Hips", "Hamstrings", "Calves", "Shoulders"] },
    { type: "sleep",    kind: "title",  title: "Bed by 10:30 tonight" },
    { type: "meal",     kind: "title",  title: "Tea · 3pm" },
    { type: "activity", kind: "body",   title: "Evening stroll", body: "Half hour after dinner. Cool breeze off the river." },
    { type: "mood",     kind: "body",   title: "Wound down easy", body: "Read a few chapters. Early bedtime." },
    { type: "workout",  kind: "stat",   title: "This week",  stat: "3 workouts", sub: "On pace for 4" },
    { type: "sleep",    kind: "body",   title: "Nap · 20 min", body: "Quick reset on the couch after lunch." },
  ];

  // Drag-and-drop (pointer-based, desktop Keep uses drag)
  const onDragStart = (id) => () => setDragId(id);
  const onDragOver = (id) => (e) => { e.preventDefault(); setHoverId(id); };
  const onDragEnd = () => { setDragId(null); setHoverId(null); };
  const onDrop = (id) => (e) => {
    e.preventDefault();
    if (dragId === null || dragId === id) { onDragEnd(); return; }
    const next = order.slice();
    const from = next.indexOf(dragId), to = next.indexOf(id);
    next.splice(to, 0, next.splice(from, 1)[0]);
    setOrder(next);
    onDragEnd();
  };

  // Split into pinned vs others, then distribute across 4 columns (desktop Keep masonry)
  const pinnedOrder = order.filter(i => pinned.has(i));
  const otherOrder = order.filter(i => !pinned.has(i) && items[i].title?.toLowerCase().includes(search.toLowerCase()));
  const cols = [[],[],[],[]];
  otherOrder.forEach((idx, i) => cols[i % 4].push(idx));
  const pcols = [[],[],[],[]];
  pinnedOrder.forEach((idx, i) => pcols[i % 4].push(idx));

  const togglePin = (idx, e) => {
    e.stopPropagation();
    const next = new Set(pinned);
    next.has(idx) ? next.delete(idx) : next.add(idx);
    setPinned(next);
  };

  const KeepCard = ({ idx }) => {
    const n = items[idx];
    const t = TYPE_COLORS_W[n.type];
    const tones = {
      workout:  "var(--dc-workout-soft)",
      meal:     "var(--dc-meal-soft)",
      sleep:    "var(--dc-sleep-soft)",
      mood:     "var(--dc-mood-soft)",
      activity: "var(--dc-activity-soft)",
    };
    const isDrag = dragId === idx;
    const isHover = hoverId === idx && dragId !== null && dragId !== idx;
    const isPinned = pinned.has(idx);
    return (
      <div
        className={"keep-card" + (isDrag ? " drag" : "") + (isHover ? " drop-target" : "")}
        style={{ background: tones[n.type], borderColor: t.dot + "33" }}
        draggable
        onDragStart={onDragStart(idx)}
        onDragOver={onDragOver(idx)}
        onDragEnd={onDragEnd}
        onDrop={onDrop(idx)}
      >
        <button className="keep-pin" onClick={(e) => togglePin(idx, e)} aria-label={isPinned ? "Unpin" : "Pin"} title={isPinned ? "Unpin" : "Pin"}>
          <Icn name={isPinned ? "pin-off" : "pin"} style={{width:14, height:14, color: isPinned ? "var(--dc-sage-deep)" : "var(--fg-2)"}} />
        </button>
        <div className="keep-head">
          <span className="dot" style={{ background: t.dot }}></span>
          <span className="lbl">{t.label}</span>
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
        {n.kind === "quote" && <div className="keep-quote">"{n.body}"</div>}
        <div className="keep-actions">
          <button aria-label="Color"><Icn name="palette" style={{width:13, height:13}} /></button>
          <button aria-label="Archive"><Icn name="archive" style={{width:13, height:13}} /></button>
          <button aria-label="More"><Icn name="more-vertical" style={{width:13, height:13}} /></button>
        </div>
      </div>
    );
  };

  return (
    <main className="main cards-main">
      <div className="topnav">
        <div>
          <div className="eyebrow">Thursday · April 23</div>
          <h1>Your notes</h1>
        </div>
        <div className="actions">
          <div className="search-field">
            <Icn name="search" style={{width:14, height:14, color:"var(--fg-2)"}} />
            <input placeholder="Search notes" value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
          <button className="btn secondary"><Icn name="layout-grid" /> Grid</button>
          <button className="btn primary"><Icn name="plus" /> New note</button>
        </div>
      </div>

      {pinnedOrder.length > 0 && (
        <>
          <div className="keep-section">Pinned</div>
          <div className="keep-board">
            {pcols.map((col, ci) => (
              <div key={ci} className="keep-col">{col.map(idx => <KeepCard key={idx} idx={idx} />)}</div>
            ))}
          </div>
          <div className="keep-section" style={{marginTop: 28}}>Others</div>
        </>
      )}
      <div className="keep-board">
        {cols.map((col, ci) => (
          <div key={ci} className="keep-col">{col.map(idx => <KeepCard key={idx} idx={idx} />)}</div>
        ))}
      </div>
    </main>
  );
};

window.Cards = Cards;
