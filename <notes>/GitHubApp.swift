// Регистрация приложения на GitHub для входа по коду (Device Flow).
//
// Client ID не секрет: в Device Flow без client secret он и так виден любому, кто запустит приложение.
// Получить его: github.com/settings/developers → New OAuth App → включить «Enable Device Flow».
// Пока nil, кнопка «войти через github» объясняет, что вход ещё не настроен.
enum GitHubApp {
    static let clientID: String? = nil
}
