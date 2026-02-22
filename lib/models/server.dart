class VpnServer {
  final String id;
  final String country;
  final String flag;
  final String city;
  final int ping;
  final int load;
  final String mode;

  const VpnServer({
    required this.id, required this.country, required this.flag,
    required this.city, required this.ping, required this.load, required this.mode,
  });

  static const defaults = [
    VpnServer(id: '1', country: 'Турция',           flag: '🇹🇷', city: 'Стамбул',  ping: 24, load: 42, mode: 'ByeDPI'),
    VpnServer(id: '2', country: 'Египет',            flag: '🇪🇬', city: 'Каир',     ping: 38, load: 61, mode: 'AmneziaWG'),
    VpnServer(id: '3', country: 'ОАЭ',               flag: '🇦🇪', city: 'Дубай',    ping: 31, load: 35, mode: 'AmneziaWG'),
    VpnServer(id: '4', country: 'Пакистан',          flag: '🇵🇰', city: 'Карачи',   ping: 55, load: 28, mode: 'Hybrid'),
    VpnServer(id: '5', country: 'Индонезия',         flag: '🇮🇩', city: 'Джакарта', ping: 72, load: 19, mode: 'ByeDPI'),
    VpnServer(id: '6', country: 'Саудовская Аравия', flag: '🇸🇦', city: 'Эр-Рияд',  ping: 44, load: 53, mode: 'AmneziaWG'),
  ];
}
