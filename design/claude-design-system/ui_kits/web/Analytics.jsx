const Analytics = () => {
  const sleep = [6.2, 6.8, 7.1, 6.5, 7.4, 8.0, 7.2, 6.9, 7.6, 7.0, 6.8, 7.5, 7.8, 7.3];
  const weight = [170.1, 169.8, 169.9, 169.6, 169.2, 168.9, 168.7, 168.2];
  const workouts = [3, 2, 4, 3, 5, 3, 4];
  const maxW = Math.max(...workouts);

  return (
    <main className="main">
      <div className="topnav">
        <div>
          <div className="eyebrow">Last 14 days</div>
          <h1>Your progress</h1>
        </div>
        <div className="actions">
          <button className="btn secondary"><Icn name="calendar" /> Apr 10 – 23</button>
          <button className="btn secondary"><Icn name="download" /> Export</button>
        </div>
      </div>

      <div className="grid" style={{gridTemplateColumns: "1fr 1fr"}}>
        <div className="card">
          <div className="stat-row"><h3 className="stat-label">Sleep duration</h3><span className="sub">hours / night</span></div>
          <div className="stat-big"><span className="num">7h 12m</span><span className="unit">avg</span></div>
          <div className="stat-note" style={{marginBottom:8}}><span className="delta">+12m vs last 2wk</span></div>
          <LineChart data={sleep} color="var(--dc-sleep)" height={200} />
        </div>
        <div className="card">
          <div className="stat-row"><h3 className="stat-label">Weight</h3><span className="sub">lbs</span></div>
          <div className="stat-big"><span className="num">168.2</span><span className="unit">lbs</span></div>
          <div className="stat-note" style={{marginBottom:8}}><span className="delta">−1.9 over range</span></div>
          <LineChart data={weight} color="var(--dc-sage)" height={200} />
        </div>
        <div className="card">
          <div className="stat-row"><h3 className="stat-label">Workouts · by week</h3><span className="sub">last 7 weeks</span></div>
          <div style={{display:"flex", alignItems:"flex-end", gap:14, height:200, paddingTop:20}}>
            {workouts.map((v, i) => (
              <div key={i} style={{flex:1, display:"flex", flexDirection:"column", alignItems:"center", gap:8}}>
                <div style={{width:"100%", background:"var(--dc-workout)", opacity: 0.3 + (v/maxW)*0.7, height: `${(v/maxW)*150}px`, borderRadius: 6}}></div>
                <span style={{fontFamily:"var(--font-mono)", fontSize:10, color:"var(--fg-2)"}}>W{i+1}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="card">
          <div className="stat-row"><h3 className="stat-label">Mood distribution</h3><span className="sub">this month</span></div>
          <div style={{display:"flex", flexDirection:"column", gap:14, marginTop: 12}}>
            {[
              { l: "Focused", v: 42, c: "var(--dc-mood)" },
              { l: "Calm",    v: 28, c: "var(--dc-activity)" },
              { l: "Tired",   v: 18, c: "var(--dc-warm-gray)" },
              { l: "Anxious", v: 8,  c: "var(--dc-workout)" },
              { l: "Elated",  v: 4,  c: "var(--dc-honey)" },
            ].map((m, i) => (
              <div key={i} style={{display:"grid", gridTemplateColumns:"80px 1fr 40px", alignItems:"center", gap:12}}>
                <span style={{fontSize:13, fontWeight:500}}>{m.l}</span>
                <div style={{height:10, background:"var(--dc-taupe)", borderRadius: 999, overflow:"hidden"}}>
                  <div style={{width:`${m.v*2}%`, height:"100%", background:m.c}}></div>
                </div>
                <span style={{fontFamily:"var(--font-mono)", fontSize:11, color:"var(--fg-2)", textAlign:"right"}}>{m.v}%</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
};

window.Analytics = Analytics;
