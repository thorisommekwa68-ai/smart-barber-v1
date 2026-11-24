import http from "node:http";
import { pathToFileURL } from "node:url";
import { createApplication } from "./app.js";
import { createStructuredLogger } from "./utils/logger.js";

const logger = createStructuredLogger();

export function createNodeServer(application) {
  return http.createServer((req, res) => {
    application.handleRequest(req, res).catch((error) => {
      logger.error("server_request_failed", { code: error?.code || "INTERNAL_ERROR" });
      res.statusCode = 500;
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify({ success: false, error: { code: "INTERNAL_ERROR", message: "An unexpected error occurred" } }));
    });
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const application = createApplication();
  const { config } = application;
  const server = createNodeServer(application);
  server.listen(config.port, () => {
    logger.info("backend_started", { port: config.port, environment: config.environment, repository: config.repositoryType });
  });
}
