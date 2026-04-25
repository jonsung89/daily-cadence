const ProgressChart = () => {
  // Sample data - sleep hours over 14 days
  const data = [6.2, 6.8, 7.1, 6.5, 7.4, 8.0, 7.2, 6.9, 7.6, 7.0, 6.8, 7.5, 7.8, 7.3];
  const w = 320, h = 160, pad = 10;
  const max = 9, min = 5;
  const stepX = (w - pad * 2) / (data.length - 1);
  const points = data.map((v, i) => {
    const x = pad + i * stepX;
    const y = pad + (1 - (v - min) / (max - min)) * (h - pad * 2);
    return [x, y];
  });
  const path = points.map(([x, y], i) => (i === 0 ? `M${x},${y}` : `L${x},${y}`)).join(" ");
  const area = path + ` L${points[points.length-1][0]},${h-pad} L${pad},${h-pad} Z`;

  return (
    <>
      <TopBar sub="Last 14 days" title="Sleep progress"
        left={<button className="iconbtn"><Icon name="chevron-left" /></button>}
        right={<button className="iconbtn"><Icon name="more-horizontal" /></button>} />
      <div className="content">
        <div className="chart-card">
          <div className="chart-stat">
            <span className="num">7h 20m</span>
            <span className="unit">avg / night</span>
            <span className="delta">+12m vs last wk</span>
          </div>
          <svg viewBox={`0 0 ${w} ${h}`} width="100%" style={{display:"block"}}>
            {[0,1,2,3].map(i => (
              <line key={i} x1={pad} x2={w-pad} y1={pad + i * (h-pad*2)/3} y2={pad + i * (h-pad*2)/3}
                stroke="var(--border-1)" strokeDasharray="2 4" />
            ))}
            <path d={area} fill="var(--dc-sage)" opacity="0.12" />
            <path d={path} fill="none" stroke="var(--dc-sage)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
            {points.map(([x,y], i) => i === points.length - 1 && (
              <g key={i}>
                <circle cx={x} cy={y} r="9" fill="var(--dc-sage)" opacity="0.15" />
                <circle cx={x} cy={y} r="4" fill="var(--dc-sage)" stroke="var(--bg-2)" strokeWidth="2" />
              </g>
            ))}
          </svg>
          <div style={{display:"flex", justifyContent:"space-between", marginTop:8, fontFamily:"var(--font-mono)", fontSize:10, color:"var(--fg-2)"}}>
            <span>Apr 10</span><span>Apr 16</span><span>Apr 23</span>
          </div>
        </div>

        <div className="section-label">This week</div>
        <div className="wgrid">
          <div className="w"><div className="lbl">Best night</div><div className="big">8h 12m</div><div className="sub">Tuesday</div></div>
          <div className="w"><div className="lbl">Consistency</div><div className="big">7/7</div><div className="sub">Nights logged</div></div>
        </div>
      </div>
    </>
  );
};

window.ProgressChart = ProgressChart;
