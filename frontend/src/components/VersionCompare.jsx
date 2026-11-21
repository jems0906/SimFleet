export default function VersionCompare({ rows = [], regressions = [] }) {
  return <article className="panel"><h2>Version comparison</h2>
    <div className="metrics">
      {rows.map(row => <div className="metric" key={`${row.driver_version}-${row.category}`}><strong>{(row.pass_rate * 100).toFixed(1)}%</strong><span>{row.driver_version} / {row.category}</span></div>)}
    </div>
    {regressions.length > 0 && <table><thead><tr><th>Scenario</th><th>Drop</th><th>Z-score</th></tr></thead><tbody>{regressions.map(r => <tr key={r.scenario_id}><td>{r.name}</td><td className="regression">-{(r.pass_rate_drop * 100).toFixed(1)} pts</td><td>{r.z_score}</td></tr>)}</tbody></table>}
  </article>;
}
