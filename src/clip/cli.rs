// flea --clip: the terminal and test seam over the clipboard; shape errors belong to usage() in main.rs.
use super::control;
use super::own;
use super::reply;

pub fn get() -> i32 {
    match control::get() {
        Ok(got) => {
            println!("{}", reply::reply_get(true, Some(&got), ""));
            0
        }
        Err(e) => {
            println!("{}", reply::reply_get(false, None, &e));
            2
        }
    }
}

pub fn set(op: &str) -> i32 {
    let input = match own::read_capped_stdin() {
        Ok(input) => input,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    let mut parts: Vec<&[u8]> = input.split(|b| *b == 0).collect();
    if parts.last() == Some(&b"".as_slice()) {
        parts.pop();
    }
    let mut paths = Vec::with_capacity(parts.len());
    for p in parts {
        match std::str::from_utf8(p) {
            Ok(s) => paths.push(s.to_string()),
            Err(_) => {
                eprintln!("flea: a clipboard path is not text");
                return 2;
            }
        }
    }
    match own::spawn_owner(op, &paths) {
        Ok(token) => {
            println!("{}", token);
            0
        }
        Err(e) => {
            eprintln!("flea: {}", e);
            2
        }
    }
}

pub fn clear(token: &str) -> i32 {
    if token.is_empty() {
        eprintln!("flea: the token names the copy to clear");
        return 2;
    }
    match control::clear(token) {
        Ok(cleared) => {
            println!("{}", reply::reply_clear(true, cleared, ""));
            0
        }
        Err(e) => {
            println!("{}", reply::reply_clear(false, false, &e));
            2
        }
    }
}

// Kept beside validate_clip_paths so the CLI and the backend refuse the same shapes.
#[cfg(test)]
mod tests {
    #[test]
    fn only_copy_and_cut_own() {
        assert!(crate::clip::format::is_op("copy") && crate::clip::format::is_op("cut"));
        assert!(!crate::clip::format::is_op("move"));
    }
}
