// The backend and flea --clip get|clear print this JSON shape; flea --clip set prints the bare token a shell script captures.
pub struct Got {
    pub clip: String,
    pub paths: Vec<String>,
    pub token: String,
    pub skipped: usize,
}

pub fn reply_set(ok: bool, token: &str, error: &str) -> String {
    if ok {
        return format!(r#"{{"t":"clip","op":"set","ok":true,"token":"{}"}}"#, crate::json::escape(token));
    }
    format!(r#"{{"t":"clip","op":"set","ok":false,"error":"{}"}}"#, crate::json::escape(error))
}

pub fn reply_get(ok: bool, got: Option<&Got>, error: &str) -> String {
    let Some(got) = got else {
        return format!(r#"{{"t":"clip","op":"get","ok":false,"error":"{}"}}"#, crate::json::escape(error));
    };
    let mut out = format!(r#"{{"t":"clip","op":"get","ok":{},"clip":"{}","paths":["#, ok, crate::json::escape(&got.clip));
    for (i, p) in got.paths.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        out.push_str(&crate::json::escape(p));
        out.push('"');
    }
    out.push_str(&format!(r#"],"token":"{}","skipped":{}}}"#, crate::json::escape(&got.token), got.skipped));
    out
}

pub fn reply_clear(ok: bool, cleared: bool, error: &str) -> String {
    if ok {
        return format!(r#"{{"t":"clip","op":"clear","ok":true,"cleared":{}}}"#, cleared);
    }
    format!(r#"{{"t":"clip","op":"clear","ok":false,"error":"{}"}}"#, crate::json::escape(error))
}
