# frozen_string_literal: true

PgEventstore.connection.with do |conn|
  types = conn.exec('select type from events group by type').to_a.map { |attrs| attrs['type'] }
  types.each.with_index(1) do |type, index|
    id = conn.exec_params('SELECT id FROM event_types WHERE type = $1', [type]).to_a.first['id']
    id ||= conn.exec_params('INSERT INTO event_types (type) VALUES ($1) RETURNING *', [type]).to_a.first['id']
    conn.exec_params('UPDATE events SET event_type_id = $1 WHERE type = $2 AND event_type_id IS NULL', [id, type])
    puts "Processed #{index} types of #{types.size}"
  end
end
