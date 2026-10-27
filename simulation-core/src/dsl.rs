//! Small, bounded, typed decision language. No host-language evaluation or I/O.
use crate::GoalPolicy;
use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Number(f64),
    Word(String),
    Bool(bool),
}
#[derive(Clone, Debug)]
pub enum Expr {
    Literal(Value),
    Field(String),
    Not(Box<Expr>),
    Binary(String, Box<Expr>, Box<Expr>),
}
impl Expr {
    pub fn eval(&self, get: &impl Fn(&str) -> Value) -> Value {
        match self {
            Self::Literal(v) => v.clone(),
            Self::Field(f) => get(f),
            Self::Not(e) => Value::Bool(e.eval(get) != Value::Bool(true)),
            Self::Binary(op, a, b) => {
                let a = a.eval(get);
                let b = b.eval(get);
                Value::Bool(match op.as_str() {
                    "and" => a == Value::Bool(true) && b == Value::Bool(true),
                    "or" => a == Value::Bool(true) || b == Value::Bool(true),
                    "==" => a == b,
                    "!=" => a != b,
                    _ => {
                        if let (Value::Number(a), Value::Number(b)) = (a, b) {
                            match op.as_str() {
                                "<" => a < b,
                                "<=" => a <= b,
                                ">" => a > b,
                                ">=" => a >= b,
                                _ => false,
                            }
                        } else {
                            false
                        }
                    }
                })
            }
        }
    }
    fn needs_target(&self) -> bool {
        match self {
            Self::Field(f) => !f.starts_with("self.") && !f.starts_with("floor."),
            Self::Not(e) => e.needs_target(),
            Self::Binary(_, a, b) => a.needs_target() || b.needs_target(),
            _ => false,
        }
    }
}
#[derive(Clone, Debug)]
pub struct Rule {
    pub name: String,
    pub target: Option<String>,
    pub filter: Option<Expr>,
    pub condition: Option<Expr>,
    pub action: String,
    pub distance_band: Option<(u32, u32)>,
}
#[derive(Clone, Debug, Default)]
pub struct Program {
    pub policy: BTreeMap<String, u32>,
    pub rules: Vec<Rule>,
}
impl Program {
    pub fn parse(source: &str) -> Result<Self, String> {
        if source.len() > 16384 {
            return Err("DSL: source must be at most 16 KB".into());
        }
        Parser::new(source)?.program()
    }
    pub fn apply(&self, mut policy: GoalPolicy) -> Result<GoalPolicy, String> {
        for (key, value) in &self.policy {
            match key.as_str() {
                "enemy_weight" => policy.enemy_weight = *value,
                "treasure_weight" => policy.item_weight = *value,
                "stairs_weight" => policy.stairs_weight = *value,
                "temperature" => policy.temperature = *value,
                _ => unreachable!(),
            }
        }
        policy.validate()
    }
}
#[derive(Clone, Debug)]
struct Token {
    text: String,
    quoted: bool,
    line: usize,
    column: usize,
}
struct Parser {
    tokens: Vec<Token>,
    index: usize,
    depth: usize,
}
impl Parser {
    fn new(source: &str) -> Result<Self, String> {
        let chars: Vec<char> = source.chars().collect();
        let mut tokens = Vec::new();
        let (mut i, mut line, mut column) = (0, 1, 1);
        while i < chars.len() {
            let c = chars[i];
            if c.is_whitespace() {
                if c == '\n' {
                    line += 1;
                    column = 0;
                }
                i += 1;
                column += 1;
                continue;
            }
            if c == '#' {
                while i < chars.len() && chars[i] != '\n' {
                    i += 1;
                    column += 1;
                }
                continue;
            }
            let start = column;
            let mut text = String::new();
            let quoted = c == '"';
            if quoted {
                i += 1;
                column += 1;
                while i < chars.len() && chars[i] != '"' {
                    if chars[i] == '\n' || chars[i] == '\\' {
                        return Err(format!("DSL line {line}, column {column}: rule names cannot contain newlines or escapes"));
                    }
                    text.push(chars[i]);
                    i += 1;
                    column += 1;
                }
                if i == chars.len() {
                    return Err(format!("DSL line {line}, column {start}: unclosed string"));
                }
                i += 1;
                column += 1;
            } else if c.is_ascii_alphanumeric() || c == '_' || c == '.' {
                while i < chars.len()
                    && (chars[i].is_ascii_alphanumeric() || chars[i] == '_' || chars[i] == '.')
                {
                    text.push(chars[i]);
                    i += 1;
                    column += 1;
                }
            } else if "{}()=<>!".contains(c) {
                text.push(c);
                i += 1;
                column += 1;
                if i < chars.len() && chars[i] == '=' && "=<>!".contains(c) {
                    text.push('=');
                    i += 1;
                    column += 1;
                }
            } else {
                return Err(format!(
                    "DSL line {line}, column {column}: unexpected character {c:?}"
                ));
            }
            tokens.push(Token {
                text,
                quoted,
                line,
                column: start,
            });
            if tokens.len() > 4096 {
                return Err("DSL: too many tokens (maximum 4096)".into());
            }
        }
        tokens.push(Token {
            text: "<end>".into(),
            quoted: false,
            line,
            column,
        });
        Ok(Self {
            tokens,
            index: 0,
            depth: 0,
        })
    }
    fn error(&self, message: &str) -> String {
        let t = &self.tokens[self.index];
        format!(
            "DSL line {}, column {}: {message}; found {:?}",
            t.line, t.column, t.text
        )
    }
    fn at(&self, text: &str) -> bool {
        !self.tokens[self.index].quoted && self.tokens[self.index].text == text
    }
    fn take(&mut self) -> String {
        let s = self.tokens[self.index].text.clone();
        if self.index + 1 < self.tokens.len() {
            self.index += 1;
        }
        s
    }
    fn eat(&mut self, text: &str) -> bool {
        if self.at(text) {
            self.take();
            true
        } else {
            false
        }
    }
    fn expect(&mut self, text: &str) -> Result<(), String> {
        if self.eat(text) {
            Ok(())
        } else {
            Err(self.error(&format!("expected {text}")))
        }
    }
    fn program(mut self) -> Result<Program, String> {
        let mut p = Program::default();
        let mut policy_seen = false;
        let mut fallback_seen = false;
        while !self.at("<end>") {
            if self.eat("policy") {
                if policy_seen {
                    return Err(self.error("duplicate policy block"));
                }
                policy_seen = true;
                self.expect("{")?;
                while !self.eat("}") {
                    if ![
                        "enemy_weight",
                        "treasure_weight",
                        "stairs_weight",
                        "temperature",
                    ]
                    .iter()
                    .any(|k| self.at(k))
                    {
                        return Err(self.error("unknown policy setting"));
                    }
                    let key = self.take();
                    self.expect("=")?;
                    if self.tokens[self.index].quoted {
                        return Err(self.error("expected an unquoted integer"));
                    }
                    let value: u32 = self.tokens[self.index]
                        .text
                        .parse()
                        .map_err(|_| self.error("expected nonnegative integer"))?;
                    let (min, max) = if key == "temperature" {
                        (1, 100)
                    } else {
                        (0, 1000)
                    };
                    if !(min..=max).contains(&value) {
                        return Err(self.error(&format!("{key} must be in {min}..{max}")));
                    }
                    self.take();
                    if p.policy.insert(key, value).is_some() {
                        return Err(self.error("duplicate policy setting"));
                    }
                }
            } else if self.eat("rule") {
                if p.rules.len() >= 64 {
                    return Err(self.error("maximum 64 rules"));
                }
                if !self.tokens[self.index].quoted || self.tokens[self.index].text.is_empty() {
                    return Err(self.error("expected a nonempty quoted rule name"));
                }
                let name = self.take();
                if p.rules.iter().any(|r| r.name == name) {
                    return Err(self.error("duplicate rule name"));
                }
                self.expect("{")?;
                let mut r = Rule {
                    name,
                    target: None,
                    filter: None,
                    condition: None,
                    action: String::new(),
                    distance_band: None,
                };
                if self.eat("target") {
                    self.expect("nearest")?;
                    if !["enemy", "item", "stairs"].iter().any(|k| self.at(k)) {
                        return Err(self.error("expected enemy, item or stairs"));
                    }
                    r.target = Some(self.take());
                    if self.eat("where") {
                        let (e, t) = self.expr(0)?;
                        if t != "bool" {
                            return Err(self.error("where requires a boolean"));
                        }
                        r.filter = Some(e);
                    }
                }
                if self.eat("when") {
                    let (e, t) = self.expr(0)?;
                    if t != "bool" {
                        return Err(self.error("when requires a boolean"));
                    }
                    r.condition = Some(e);
                }
                self.expect("do")?;
                if ![
                    "shoot",
                    "attack",
                    "move_toward",
                    "keep_distance",
                    "use_potion",
                    "wait",
                ]
                .iter()
                .any(|k| self.at(k))
                {
                    return Err(self.error("unknown action"));
                }
                r.action = self.take();
                if ["shoot", "attack", "move_toward", "keep_distance"].contains(&r.action.as_str())
                {
                    self.expect("target")?;
                    if r.target.is_none() {
                        return Err(self.error("action requires a target declaration"));
                    }
                    if r.action != "move_toward" && r.target.as_deref() != Some("enemy") {
                        return Err(
                            self.error("shoot/attack/keep_distance require an enemy target")
                        );
                    }
                }
                if r.action == "keep_distance" {
                    self.expect("min")?;
                    self.expect("=")?;
                    let minimum = self.distance_bound()?;
                    self.expect("max")?;
                    self.expect("=")?;
                    let maximum = self.distance_bound()?;
                    if minimum > maximum {
                        return Err(self.error("keep_distance requires min <= max"));
                    }
                    r.distance_band = Some((minimum, maximum));
                }
                if r.target.is_none() && r.condition.as_ref().is_some_and(Expr::needs_target) {
                    return Err(self.error("target field requires a target declaration"));
                }
                self.expect("}")?;
                p.rules.push(r);
            } else if self.eat("fallback") {
                if fallback_seen {
                    return Err(self.error("duplicate fallback"));
                }
                fallback_seen = true;
                self.expect("explore")?;
            } else {
                return Err(self.error("expected policy, rule or fallback"));
            }
        }
        Ok(p)
    }

    fn distance_bound(&mut self) -> Result<u32, String> {
        let token = &self.tokens[self.index];
        let number = token.text.parse::<u32>().ok();
        if token.quoted || !number.is_some_and(|n| (1..=100).contains(&n)) {
            return Err(self.error("distance bound must be an unquoted integer in 1..100"));
        }
        self.take();
        Ok(number.unwrap())
    }
    fn expr(&mut self, min: u8) -> Result<(Expr, &'static str), String> {
        self.depth += 1;
        if self.depth > 32 {
            return Err(self.error("expression nesting exceeds 32"));
        }
        let (mut left, mut ty) = if self.eat("not") {
            let (e, t) = self.expr(4)?;
            if t != "bool" {
                return Err(self.error("not requires a boolean"));
            }
            (Expr::Not(Box::new(e)), "bool")
        } else if self.eat("(") {
            let e = self.expr(0)?;
            self.expect(")")?;
            e
        } else {
            let token = self.tokens[self.index].clone();
            if token.quoted {
                return Err(self.error("use unquoted enum values in conditions"));
            }
            let text = token.text.as_str();
            let field_type = match text {
                "self.hp" | "self.max_hp" | "self.hp_percent" | "self.potions" | "self.attack"
                | "target.hp" | "hp" | "target.distance" | "distance" | "floor.enemy_count" => {
                    Some("number")
                }
                "self.weapon" => Some("weapon"),
                "target.type" | "type" => Some("kind"),
                "target.shootable" | "shootable" | "target.visible" | "visible" => Some("bool"),
                _ => None,
            };
            if let Some(t) = field_type {
                (Expr::Field(self.take()), t)
            } else if ["true", "false"].contains(&text) {
                (Expr::Literal(Value::Bool(self.take() == "true")), "bool")
            } else if ["bow", "melee"].contains(&text) {
                (Expr::Literal(Value::Word(self.take())), "weapon")
            } else if [
                "archer",
                "brute",
                "health_potion",
                "weapon",
                "armor",
                "stairs",
            ]
            .contains(&text)
            {
                (Expr::Literal(Value::Word(self.take())), "kind")
            } else if let Ok(n) = text.parse::<f64>() {
                if !n.is_finite() || n > 1_000_000.0 {
                    return Err(self.error("number out of range"));
                }
                self.take();
                (Expr::Literal(Value::Number(n)), "number")
            } else {
                return Err(self.error("unknown field or value"));
            }
        };
        loop {
            if self.tokens[self.index].quoted {
                break;
            }
            let op = self.tokens[self.index].text.clone();
            let prec = match op.as_str() {
                "or" => 1,
                "and" => 2,
                "==" | "!=" | "<" | "<=" | ">" | ">=" => 3,
                _ => break,
            };
            if prec < min {
                break;
            }
            self.take();
            let (right, rt) = self.expr(prec + 1)?;
            let melee = |e: &Expr| matches!(e, Expr::Literal(Value::Word(s)) if s == "melee");
            let compatible =
                ty == rt || (ty == "kind" && melee(&right)) || (rt == "kind" && melee(&left));
            if !compatible
                || (prec < 3 && ty != "bool")
                || (["<", "<=", ">", ">="].contains(&op.as_str()) && ty != "number")
            {
                return Err(self.error("incompatible expression types"));
            }
            left = Expr::Binary(op, Box::new(left), Box::new(right));
            ty = "bool";
        }
        self.depth -= 1;
        Ok((left, ty))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn syntax_and_types_are_validated() {
        let p = Program::parse("# comment\npolicy { treasure_weight = 5 } rule \"反撃\" { target nearest enemy where type == archer and shootable when self.weapon == bow do shoot target }").unwrap();
        assert_eq!(p.rules.len(), 1);
        assert_eq!(p.policy["treasure_weight"], 5);
        for source in [
            "policy { treasure_weigth = 1 }",
            "rule \"x\" { when self.hpp < 5 do wait }",
            "rule \"x\" { when self.hp == bow do wait }",
            "rule \"x\" { do shoot target }",
            "rule \"x\" { when target.hp < 5 do wait }",
            "rule \"x\" { do waait }",
            "policy { enemy_weight = 1 enemy_weight = 2 }",
            "rule \"x\" { do wait } rule \"x\" { do wait }",
            "rule \"x\" { when self.hp do wait }",
            "rule \"x\" { do wait",
            "rule \"x\" { target nearest item do shoot target }",
            "policy { temperature = 0 }",
        ] {
            assert!(
                Program::parse(source).unwrap_err().contains("line"),
                "{source}"
            );
        }
    }
    #[test]
    fn distance_action_and_floor_conditions_are_checked_before_execution() {
        let program = Program::parse("rule \"Space\" { target nearest enemy when floor.enemy_count > 0 do keep_distance target min = 3 max = 5 } rule \"Clear\" { when floor.enemy_count == 0 do wait }").unwrap();
        assert_eq!(program.rules[0].distance_band, Some((3, 5)));
        assert_eq!(program.rules[1].target, None);
        assert!(!program.rules[1].condition.as_ref().unwrap().needs_target());
        for source in [
            "rule \"x\" { do keep_distance target min = 3 max = 5 }",
            "rule \"x\" { target nearest item do keep_distance target min = 3 max = 5 }",
            "rule \"x\" { target nearest stairs do keep_distance target min = 3 max = 5 }",
            "rule \"x\" { target nearest enemy do keep_distance target }",
            "rule \"x\" { target nearest enemy do keep_distance target min = 0 max = 5 }",
            "rule \"x\" { target nearest enemy do keep_distance target min = 6 max = 5 }",
            "rule \"x\" { target nearest enemy do keep_distance target min = 1 max = 101 }",
            "rule \"x\" { target nearest enemy do keep_distance target min = 2.5 max = 5 }",
            "rule \"x\" { target nearest enemy do keep_distance target min = \"3\" max = 5 }",
            "rule \"x\" { target nearest enemy do keep_distance target min = 3 }",
            "rule \"x\" { target nearest enemy do keep_distance target max = 5 min = 3 }",
            "rule \"x\" { when floor.enemy_count do wait }",
            "rule \"x\" { when floor.enemy_count == bow do wait }",
            "rule \"x\" { when floor.enemies_count == 0 do wait }",
            "rule \"x\" { when enemy_count == 0 do wait }",
        ] {
            assert!(
                Program::parse(source).unwrap_err().contains("line"),
                "{source}"
            );
        }
    }
    #[test]
    fn boolean_precedence_and_empty_defaults() {
        assert!(Program::parse("").unwrap().rules.is_empty());
        let p = Program::parse(
            "rule \"x\" { when self.hp < 5 or self.potions > 0 and not false do wait }",
        )
        .unwrap();
        assert_eq!(
            p.rules[0]
                .condition
                .as_ref()
                .unwrap()
                .eval(&|_| Value::Number(0.0)),
            Value::Bool(true)
        );
    }
}
