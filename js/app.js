// ICT Service Request Management System — dashboard logic
let requests = [];
let editMode = false;
const elements = {};

document.addEventListener("DOMContentLoaded", async () => {
  Object.assign(elements, {
    requestForm: document.getElementById("requestForm"), requestModal: document.getElementById("requestModal"), modalTitle: document.getElementById("modalTitle"), requestId: document.getElementById("requestId"), requester: document.getElementById("requester"), department: document.getElementById("department"), category: document.getElementById("category"), description: document.getElementById("description"), priority: document.getElementById("priority"), status: document.getElementById("status"), tableBody: document.getElementById("tableBody"), dataMessage: document.getElementById("dataMessage"), search: document.getElementById("search"), statusFilter: document.getElementById("statusFilter"), priorityFilter: document.getElementById("priorityFilter"), totalCount: document.getElementById("totalCount"), pendingCount: document.getElementById("pendingCount"), progressCount: document.getElementById("progressCount"), completedCount: document.getElementById("completedCount")
  });
  bindEvents();
  const user = await getCurrentUser();
  if (user) await loadRequests();
});

function bindEvents() {
  document.getElementById("newBtn").addEventListener("click", () => openRequestModal());
  document.getElementById("cancelBtn").addEventListener("click", closeRequestModal);
  document.getElementById("closeModalBtn").addEventListener("click", closeRequestModal);
  elements.requestModal.addEventListener("click", (event) => { if (event.target === elements.requestModal) closeRequestModal(); });
  document.addEventListener("keydown", (event) => { if (event.key === "Escape" && !elements.requestModal.hidden) closeRequestModal(); });
  elements.requestForm.addEventListener("submit", saveRequest);
  elements.search.addEventListener("input", filterData);
  elements.statusFilter.addEventListener("change", filterData);
  elements.priorityFilter.addEventListener("change", filterData);
}

async function loadRequests() {
  setDataMessage("Loading requests…", "loading");
  const { data, error } = await supabaseClient.from("service_requests").select("id, requester_name, department, category, description, priority, status, created_at, user_id").order("created_at", { ascending: false });
  if (error) {
    console.error("Unable to load service requests:", error);
    requests = []; displayRequests([]); updateDashboard([]);
    setDataMessage(`Could not load requests: ${error.message}`, "error"); return;
  }
  requests = data || []; updateDashboard(requests); filterData();
}

function displayRequests(data) {
  elements.tableBody.replaceChildren();
  if (!data.length) {
    const row = document.createElement("tr");
    row.innerHTML = '<td colspan="8" class="empty-state">No requests found. Create your first request to get started.</td>';
    elements.tableBody.appendChild(row); return;
  }
  data.forEach((request) => {
    const row = document.createElement("tr");
    appendCell(row, `#${request.id}`, "request-id"); appendCell(row, request.requester_name); appendCell(row, request.department); appendCell(row, request.category);
    appendBadgeCell(row, request.priority, "priority"); appendBadgeCell(row, request.status, "status"); appendCell(row, formatDate(request.created_at));
    const actions = document.createElement("td"); actions.className = "actions";
    actions.append(actionButton("Edit", "edit-btn", () => editRequest(request.id)), actionButton("Delete", "delete-btn", () => deleteRequest(request.id)));
    row.appendChild(actions); elements.tableBody.appendChild(row);
  });
}
function appendCell(row, value, className = "") { const cell = document.createElement("td"); cell.textContent = value || "—"; if (className) cell.className = className; row.appendChild(cell); }
function appendBadgeCell(row, value, type) { const cell = document.createElement("td"); const badge = document.createElement("span"); badge.className = `${type}-badge ${String(value).toLowerCase().replace(/\s+/g, "-")}`; badge.textContent = value || "—"; cell.appendChild(badge); row.appendChild(cell); }
function actionButton(label, className, handler) { const button = document.createElement("button"); button.type = "button"; button.className = className; button.textContent = label; button.addEventListener("click", handler); return button; }

function filterData() {
  const keyword = elements.search.value.trim().toLowerCase();
  const filtered = requests.filter((request) => {
    const searchable = [request.requester_name, request.department, request.category, request.description].filter(Boolean).join(" ").toLowerCase();
    return searchable.includes(keyword) && (!elements.statusFilter.value || request.status === elements.statusFilter.value) && (!elements.priorityFilter.value || request.priority === elements.priorityFilter.value);
  });
  displayRequests(filtered); setDataMessage(`${filtered.length} ${filtered.length === 1 ? "request" : "requests"} shown`, "success");
}
function updateDashboard(data) { elements.totalCount.textContent = data.length; elements.pendingCount.textContent = data.filter((r) => r.status === "Pending").length; elements.progressCount.textContent = data.filter((r) => r.status === "In Progress").length; elements.completedCount.textContent = data.filter((r) => r.status === "Completed").length; }

function openRequestModal(request = null) {
  editMode = Boolean(request); elements.requestForm.reset(); elements.requestId.value = request?.id || "";
  elements.modalTitle.textContent = request ? "Edit service request" : "New service request";
  document.getElementById("saveBtn").textContent = request ? "Save changes" : "Submit request";
  if (request) { elements.requester.value = request.requester_name || ""; elements.department.value = request.department || ""; elements.category.value = request.category || ""; elements.description.value = request.description || ""; elements.priority.value = request.priority || ""; elements.status.value = request.status || "Pending"; }
  elements.requestModal.hidden = false; document.body.classList.add("modal-open"); elements.requester.focus();
}
function closeRequestModal() { elements.requestModal.hidden = true; document.body.classList.remove("modal-open"); elements.requestForm.reset(); editMode = false; }

async function saveRequest(event) {
  event.preventDefault(); const user = await getCurrentUser(); if (!user) return;
  const payload = { requester_name: elements.requester.value.trim(), department: elements.department.value.trim(), category: elements.category.value, description: elements.description.value.trim(), priority: elements.priority.value, status: elements.status.value };
  const saveBtn = document.getElementById("saveBtn"); saveBtn.disabled = true; saveBtn.textContent = "Saving…";
  let error;
  if (editMode) ({ error } = await supabaseClient.from("service_requests").update(payload).eq("id", elements.requestId.value));
  else ({ error } = await supabaseClient.from("service_requests").insert([{ ...payload, user_id: user.id }]));
  saveBtn.disabled = false;
  if (error) { console.error("Unable to save service request:", error); saveBtn.textContent = editMode ? "Save changes" : "Submit request"; setDataMessage(`Could not save request: ${error.message}`, "error"); return; }
  closeRequestModal(); await loadRequests();
}
function editRequest(id) { const request = requests.find((item) => String(item.id) === String(id)); if (request) openRequestModal(request); }
async function deleteRequest(id) { if (!window.confirm("Delete this service request? This cannot be undone.")) return; const { error } = await supabaseClient.from("service_requests").delete().eq("id", id); if (error) { console.error("Unable to delete service request:", error); setDataMessage(`Could not delete request: ${error.message}`, "error"); return; } await loadRequests(); }
function setDataMessage(message, type) { elements.dataMessage.textContent = message; elements.dataMessage.className = `data-message ${type}`; }
function formatDate(value) { return value ? new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", year: "numeric" }).format(new Date(value)) : "—"; }
