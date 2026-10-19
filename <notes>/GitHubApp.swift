// Регистрация приложения на GitHub для входа по коду (Device Flow).
//
// Client ID не секрет: в Device Flow без client secret он и так виден любому, кто запустит приложение.
// Получить его: github.com/settings/developers → New OAuth App → включить «Enable Device Flow».
// Если поставить nil, кнопка «войти через github» объяснит, что вход не настроен.
enum GitHubApp {
    // OAuth App «<notes>» в аккаунте автора, Device Flow включён.
    static let clientID: String? = "Ov23lidTP0V2Y3bAknph"
}
