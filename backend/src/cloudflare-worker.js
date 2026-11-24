import { createApplication } from "./app.js";
import { createWorkerFetch } from "./worker.js";

export default {
  fetch: createWorkerFetch(createApplication)
};
