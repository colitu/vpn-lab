# Colitu VPN Lab

**Bilerek bozulmuş ağlarda, tekrarlanabilir VPN protokol testleri.**

Colitu YouTube kanalındaki *Dayanır mı?* (*Can It Survive?*) serisinin test laboratuvarı burası. İki Linux sunucu alıyoruz, aralarına dört VPN protokolü kuruyoruz, ağı bilerek kötüleştiriyoruz (paket kaybı, gecikme, hız sınırı) ve neyin hâlâ çalıştığını ölçüyoruz.

Videolarda gösterdiğimiz her sayı bu scriptlerden geliyor. Okuyabilir, sorgulayabilir ve kendiniz çalıştırabilirsiniz. Ayrıntılı açıklama: [README.md](README.md) (İngilizce).

## Kısaca

- **Protokoller:** WireGuard, OpenVPN (UDP), VLESS + Reality, Hysteria2 ve karşılaştırma için VPN'siz bağlantı.
- **Kötü ağ:** İstemcide Linux `tc netem`. **İki yönde de** aynı kayıp, her yöne +20 ms gecikme, 100 Mbit/s sınır. Yalnızca lab sunucusuyla olan trafik etkilenir.
- **Kayıp seviyeleri:** %0, %1, %5, %10 (yön başına; iki yönde %5, gidiş-dönüşte yaklaşık %10 eder).
- **Ölçümler:** Her seviye ve protokol için karışık sırayla 3 tekrar:
  - 64 MB indirme hızı
  - 100 KB'lık 20 "sayfa" isteğinin yüklenme süresi ve başarısız olanlar

## Kendiniz çalıştırın

```bash
# lab sunucusunda
sudo bash lab-server.sh <istemci_ip>        # sıradan site gibi: sudo LAB_CC=cubic bash lab-server.sh <istemci_ip>
# client-bundle.tgz dosyasını istemciye kopyalayın, sonra istemcide:
sudo bash lab-client.sh
sudo bash /opt/colitu-lab/lab-run.sh testim "0 1 5 10" 3
python3 analyze.py /opt/colitu-lab/results/testim.jsonl ozet.json
# temizlik
sudo bash lab-teardown.sh client            # sunucuda: sudo bash lab-teardown.sh server <istemci_ip>
```

## Sayıları alıntılamadan önce

- **TCP tıkanıklık algoritması sonucu çok etkiler.** WireGuard ve OpenVPN içinde TCP'yi web sitesinin sunucusu yönetir. BBR kayba dayanıklıdır, Linux varsayılanı CUBIC ise kayıpta belirgin şekilde yavaşlar. 1. bölümde test sitesi BBR kullandı; bu, tünel içindeki TCP için en iyi durum. CUBIC ile tünel sonuçları daha düşük çıkabilir, kendi kurulumunuzda `LAB_CC=cubic` ile deneyebilirsiniz.
- **Kayıp rastgeledir.** Gerçek Wi-Fi ve mobil ağlarda kayıp çoğu zaman toplu gelir, bu da sıralamayı değiştirebilir.
- **Tek rota, tek sunucu çifti.** Mutlak sayılar başka kurulumlarda farklı çıkar. Protokolleri aynı test içinde karşılaştırın.
- **Bu bir engelleme testi değildir.** UDP engellendiğinde ne olduğu ayrı bir bölümün konusu.

Lisans: MIT. [Colitu](https://colitu.com), Windows, Android ve Linux için açık kaynaklı bir VPN'dir.
