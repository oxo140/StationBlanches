use anyhow::{Context, Result};
use std::{
    fs,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Mount {
    pub path: PathBuf,
    pub key: String,
    pub label: String,
}

fn unescape(value: &str) -> String {
    value
        .replace("\\040", " ")
        .replace("\\011", "\t")
        .replace("\\012", "\n")
        .replace("\\134", "\\")
}

pub fn parse(info: &str, root: &Path) -> Vec<Mount> {
    info.lines()
        .filter_map(|line| {
            let (left, right) = line.split_once(" - ")?;
            let fields: Vec<_> = left.split_whitespace().collect();
            let fs_fields: Vec<_> = right.split_whitespace().collect();
            if fields.len() < 6 || fs_fields.len() < 2 || !fields[5].split(',').any(|x| x == "ro") {
                return None;
            }
            let path = PathBuf::from(unescape(fields[4]));
            if path.parent() != Some(root) || !fs_fields[1].starts_with("/dev/") {
                return None;
            }
            let label = path.file_name()?.to_string_lossy().into_owned();
            Some(Mount {
                key: format!("{}:{}:{}:{}", fields[0], fields[2], fields[3], fs_fields[1]),
                path,
                label,
            })
        })
        .collect()
}

pub fn list(root: &Path) -> Result<Vec<Mount>> {
    Ok(parse(
        &fs::read_to_string("/proc/self/mountinfo").context("Lecture des montages Linux")?,
        root,
    ))
}

pub fn still_present(mount: &Mount, root: &Path) -> bool {
    list(root).is_ok_and(|mounts| mounts.iter().any(|m| m == mount))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn accepts_only_direct_readonly_device_mounts() {
        let text = "42 20 8:17 / /media/sdb1 ro,nosuid - vfat /dev/sdb1 ro\n43 20 8:18 / /media/rw rw - ext4 /dev/sdb2 rw\n44 20 0:20 / /media/fake ro - tmpfs tmpfs ro\n45 20 8:19 / /other/disk ro - ext4 /dev/sdb3 ro\n46 20 8:20 / /media/a\\040b ro - vfat /dev/sdc1 ro";
        let result = parse(text, Path::new("/media"));
        assert_eq!(result.len(), 2);
        assert_eq!(result[1].label, "a b");
        assert_ne!(
            result[0].key,
            parse(&text.replace("42 20", "99 20"), Path::new("/media"))[0].key
        );
    }
}
