export function createStructuredLogger() {
  function write(level, event, fields = {}) {
    const record = {
      level,
      event,
      timestamp: new Date().toISOString(),
      ...fields
    };
    if (level === "error") console.error(JSON.stringify(record));
    else console.log(JSON.stringify(record));
  }
  return {
    info: (event, fields) => write("info", event, fields),
    warn: (event, fields) => write("warn", event, fields),
    error: (event, fields) => write("error", event, fields)
  };
}
