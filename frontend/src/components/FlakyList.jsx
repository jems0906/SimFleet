export default function FlakyList({ rows = [] }) {
  return <article className="panel"><h2>Flaky scenarios</h2><table><thead><tr><th>Scenario</th><th>Repeated</th><th>Disagree</th></tr></thead>
    <tbody>{rows.length ? rows.map(r => <tr key={r.scenario_id}><td>{r.name}</td><td>{r.repeated_seed_count}</td><td className="regression">{r.disagreeing_seed_count}</td></tr>) : <tr><td colSpan="3">No repeat-run disagreement</td></tr>}</tbody></table></article>;
}
