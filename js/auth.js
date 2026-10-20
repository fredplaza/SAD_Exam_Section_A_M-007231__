// ======================================
// AUTHENTICATION MODULE
// ICT Service Request Management System
// ======================================
// AUTHENTICATION MODULE
// ICT Service Request Management System
// ======================================


// ===============================
// CHECK SESSION
// ===============================

async function checkSession(){
    const { data } = await supabaseClient.auth.getSession();
    if(!data.session){
        window.location.href = "login.html";
    }
}


// ===============================
// GET CURRENT USER
// ===============================

async function getCurrentUser(){
    const { data, error } = await supabaseClient.auth.getUser();
    if(error){
        console.log(error);
        return null;
    }
    return data.user;
}


// ===============================
// LOGIN & LOGOUT HANDLERS (attach after DOM ready)
// ===============================

document.addEventListener("DOMContentLoaded", () => {

    const loginForm = document.getElementById("loginForm");
    if (loginForm) {
        loginForm.addEventListener("submit", async function (e) {
            e.preventDefault();
            const email = document.getElementById("email").value;
            const password = document.getElementById("password").value;
            const { data, error } = await supabaseClient.auth.signInWithPassword({
                email: email,
                password: password
            });
            const message = document.getElementById("loginMessage");
            if (error) {
                message.innerHTML = "Login failed: " + error.message;
                message.style.color = "red";
                return;
            }
            message.innerHTML = "Login successful...";
            message.style.color = "green";
            setTimeout(() => {
                window.location.href = "index.html";
            }, 1000);
        });
    }

    const logoutBtn = document.getElementById("logoutBtn");
    if (logoutBtn) {
        logoutBtn.addEventListener("click", async () => {
            await supabaseClient.auth.signOut();
            window.location.href = "login.html";
        });
    }

});


// ===============================
// RUN SESSION CHECK
// ===============================

if (window.location.pathname.includes("index.html")) {
    checkSession();
}