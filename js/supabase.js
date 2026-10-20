// =====================================
// SUPABASE CONFIGURATION
// ICT Service Request Management System
// =====================================


// Replace these with your Supabase project details

const SUPABASE_URL = 
"https://lqmafsdrcszdzqklnzkd.supabase.co";


const SUPABASE_KEY = 
"sb_publishable_0C1oJB2Wejo7WP6tlI_qDw_IHLmYG-f";



// Create Supabase Client and expose globally for other scripts
window.supabaseClient = supabase.createClient(
    SUPABASE_URL,
    SUPABASE_KEY
);