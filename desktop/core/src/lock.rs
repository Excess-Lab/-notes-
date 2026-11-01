//! Вход по пинкоду — как `PinCode.swift` и `LockPolicy.swift` на маке. Заметки пинкодом не шифруются
//! (иначе их не открыл бы другой редактор): пинкод закрывает приложение, а не файлы.

use pbkdf2::pbkdf2_hmac;
use serde::{Deserialize, Serialize};
use sha2::Sha256;

pub const LENGTH: usize = 4;
const ROUNDS: u32 = 200_000;

/// Пинкод храним не сам, а PBKDF2-SHA256 с солью. Четыре цифры перебираются быстро при любом хеше,
/// поэтому настоящая защита — хранилище паролей ОС, а хеш — чтобы пинкод не лежал открытым даже там.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinHash {
    salt: [u8; 16],
    hash: [u8; 32],
}

fn derive(pin: &str, salt: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    pbkdf2_hmac::<Sha256>(pin.as_bytes(), salt, ROUNDS, &mut out);
    out
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex<const N: usize>(s: &str) -> Option<[u8; N]> {
    if s.len() != N * 2 {
        return None;
    }
    let mut out = [0u8; N];
    for (i, b) in out.iter_mut().enumerate() {
        *b = u8::from_str_radix(s.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(out)
}

impl PinHash {
    pub fn new(pin: &str) -> Self {
        let mut salt = [0u8; 16];
        getrandom::getrandom(&mut salt).expect("system random");
        Self { salt, hash: derive(pin, &salt) }
    }

    pub fn matches(&self, pin: &str) -> bool {
        // Сравнение без раннего выхода: время не подсказывает, сколько байт совпало.
        derive(pin, &self.salt).iter().zip(self.hash.iter()).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
    }

    /// Одной строкой «соль:хеш» в hex — так лежит в хранилище паролей.
    pub fn encoded(&self) -> String {
        format!("{}:{}", hex(&self.salt), hex(&self.hash))
    }

    pub fn decode(s: &str) -> Option<Self> {
        let (salt, hash) = s.split_once(':')?;
        Some(Self { salt: unhex(salt)?, hash: unhex(hash)? })
    }
}

/// Только четыре цифры ASCII.
pub fn valid(pin: &str) -> bool {
    pin.len() == LENGTH && pin.bytes().all(|b| b.is_ascii_digit())
}

/// Когда спрашивать: не мешать, пока человек работает, и закрывать, когда отошёл.
pub mod policy {
    /// Приложение было свёрнуто дольше — при возврате спрашиваем снова (секунды).
    pub const IDLE_LIMIT: i64 = 15 * 60;
    /// Закрыл и сразу открыл — не спрашиваем.
    pub const RELAUNCH_GRACE: i64 = 5 * 60;

    /// `last_seen_unlocked` — когда приложение последний раз было открытым и разблокированным.
    pub fn at_launch(last_seen_unlocked: Option<i64>, now: i64) -> bool {
        match last_seen_unlocked {
            None => true,
            // Время назад (перевели часы) — подозрительно, спрашиваем.
            Some(t) => now < t || now - t > RELAUNCH_GRACE,
        }
    }

    pub fn on_return(inactive_since: Option<i64>, now: i64) -> bool {
        inactive_since.is_some_and(|t| now < t || now - t >= IDLE_LIMIT)
    }
}

/// Пауза после неверных пинкодов: 5 ошибок бесплатно (опечатки), дальше 30 с, 1 мин, 2 мин… до 15 мин.
/// Хранится между запусками: перезапуск паузу не сбрасывает.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Attempts {
    pub failures: u32,
    pub blocked_until: Option<i64>,
}

impl Attempts {
    pub const FREE: u32 = 5;

    /// Сколько секунд ещё ждать; `None` — можно вводить.
    pub fn remaining(&self, now: i64) -> Option<i64> {
        self.blocked_until.filter(|&t| t > now).map(|t| t - now)
    }

    pub fn failure(&mut self, now: i64) {
        self.failures += 1;
        if self.failures < Self::FREE {
            return;
        }
        let extra = (self.failures - Self::FREE).min(10);
        let delay = (30i64 << extra).min(15 * 60);
        self.blocked_until = Some(now + delay);
    }

    pub fn reset(&mut self) {
        *self = Self::default();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_roundtrip() {
        let h = PinHash::new("1234");
        assert!(h.matches("1234"));
        assert!(!h.matches("1235"));
        let back = PinHash::decode(&h.encoded()).unwrap();
        assert_eq!(back, h);
        assert_ne!(PinHash::new("1234").encoded(), h.encoded(), "salted");
        assert!(PinHash::decode("zz:yy").is_none());
        assert!(valid("0042") && !valid("12a4") && !valid("123") && !valid("١٢٣٤"));
    }

    #[test]
    fn lock_policy() {
        assert!(policy::at_launch(None, 1000));
        assert!(!policy::at_launch(Some(1000), 1000 + 60));
        assert!(policy::at_launch(Some(1000), 1000 + 301));
        assert!(policy::at_launch(Some(1000), 900), "clock moved back");
        assert!(!policy::on_return(None, 0));
        assert!(!policy::on_return(Some(0), 899));
        assert!(policy::on_return(Some(0), 900));
    }

    #[test]
    fn attempts_backoff() {
        let mut a = Attempts::default();
        for _ in 0..4 {
            a.failure(0);
        }
        assert_eq!(a.remaining(0), None, "four typos are free");
        a.failure(0);
        assert_eq!(a.remaining(0), Some(30));
        a.failure(100);
        assert_eq!(a.remaining(100), Some(60));
        for _ in 0..20 {
            a.failure(100);
        }
        assert_eq!(a.remaining(100), Some(900), "capped at 15 min");
        a.reset();
        assert_eq!(a, Attempts::default());
    }
}
