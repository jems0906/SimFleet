export default function BatchHealth({ rows = [] }) {
  return <article className="panel"><h2>Run health</h2><table><thead><tr><th>Batch</th><th>Version</th><th>Status</th><th>Missing</th></tr></thead>
    <tbody>{rows.map(r => <tr key={r.batch_id}><td>{String(r.batch_id).slice(0,8)}</td><td>{r.driver_version}</td><td className={r.status === "complete" ? "ok" : "regression"}>{r.status}</td><td>{r.missing_count}</td></tr>)}</tbody></table></article>;
}
