// Dev helper: query a *running* Foreman's control socket and print describe().
// Requires Foreman to be running. Uses FOREMAN_CONTROL_SOCKET or the default.
import { describe } from "../dist/control.js";

try {
  const info = await describe();
  console.log(JSON.stringify(info, null, 2));
} catch (error) {
  console.error("describe failed:", error.message);
  process.exit(1);
}
