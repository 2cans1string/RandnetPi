#include <iostream>
#include <string>
#include <cstdlib>
#include <fstream>
#include <sys/types.h>
#include <sys/unistd.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdio.h>
using namespace std;

void AddWifiNetwork(string SSID, string WifiPass, string CountryCode)
{
	
	ofstream WPASupplicant("/etc/wpa_supplicant/wpa_supplicant.conf", std::ios::out);
	if (WPASupplicant.is_open())
	{			
                WPASupplicant << "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev" << endl;
		WPASupplicant << "update_config=1\n" << endl;
                WPASupplicant << "network={" << endl;
		WPASupplicant << "ssid=\"" + SSID + "\"" << endl;
		WPASupplicant << "psk=\"" + WifiPass + "\"" << endl;
		WPASupplicant << "}\n";
		WPASupplicant.close();
		cout << endl;
		cout << "The wireless network '" + SSID + "' " + "has been added." << endl;		
	}
	else
	{
		cout << "Unable to open the network config file. Please run 'sudo wificonfig' and try again." << endl; 
	}
	
}

void AddOpenWifiNetwork(string SSID)
{
	
	ofstream WPASupplicant("/etc/wpa_supplicant/wpa_supplicant.conf", std::ios::out);
	if (WPASupplicant.is_open())
	{	
                WPASupplicant << "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev" << endl;
                WPASupplicant << "update_config=1\n" << endl;		
		WPASupplicant << "network={" << endl;
		WPASupplicant << "ssid=\"" + SSID + "\"" << endl;
		WPASupplicant << "key_mgmt=NONE" << endl;
		WPASupplicant << "}\n";
		WPASupplicant.close();
		cout << endl;
		cout << "The wireless network '" + SSID + "' " + "has been added." << endl;		
	}
	else
	{
		cout << "Unable to open the network config file. Please run 'sudo wificonfig' and try again." << endl; 
	}
	
}

void AddCountryCode(string CountryCode)
{

	ofstream WPASupplicant("/etc/wpa_supplicant/wpa_supplicant.conf", ios_base::app);
	if (WPASupplicant.is_open())
	{			
		WPASupplicant << endl << "country=" + CountryCode << endl;
		WPASupplicant.close();
		cout << endl;
		cout << "The Country Code '" + CountryCode + "' " + "has been added." << endl;		
	}
	else
	{
		cout << "Unable to open the network config file. Please run 'sudo wificonfig' and try again." << endl; 
	}

}

void EnableWifi()
{
	ofstream WPASupplicant("/etc/network/interfaces");
	if (WPASupplicant.is_open())
	{			
		WPASupplicant << "auto wlan0" << endl;
		WPASupplicant << "allow-hotplug wlan0" << endl;
		WPASupplicant << "iface wlan0 inet manual" << endl;
		WPASupplicant << "wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf" << endl;
		WPASupplicant << "iface default inet dhcp" << endl;
		WPASupplicant << "dns-nameserver 127.0.0.1" << endl << endl;
		
		WPASupplicant << "manual eth0" << endl;
		WPASupplicant << "allow-hotplug eth0" << endl;
		WPASupplicant << "iface eth0 inet dhcp" << endl;
		WPASupplicant << "dns-nameserver 127.0.0.1";
		WPASupplicant.close();
	}
	else
	{
		cout << "Unable to open the interfaces config file. Please run 'sudo wificonfig' and try again." << endl; 
	}

	//Enable Pi 3 internal Wi-Fi (if disabled) in config.txt by reverting to defaults
	ofstream bootconf("/boot/config.txt");
	if (bootconf.is_open())
	{					
		bootconf << "config_hdmi_boost=4" << endl;
		bootconf << "hdmi_force_hotplug=1" << endl;
		bootconf << "hdmi_drive=2" << endl;
		bootconf.close();
		cout << "Wi-Fi has been enabled. Please reboot the Pi for the changes to take effect." << endl;
	}
	else
	{
		cout << "Unable to open the boot config file. Please run 'sudo wificonfig' and try again." << endl; 
	}
}

void DisableWifi()
{
	//Reset interfaces to the default configuration
	ofstream WPASupplicant("/etc/network/interfaces");
	if (WPASupplicant.is_open())
	{					
		WPASupplicant << "auto eth0" << endl;
		WPASupplicant << "allow-hotplug eth0" << endl;
		WPASupplicant << "iface eth0 inet dhcp" << endl;
		WPASupplicant << "dns-nameserver 127.0.0.1";
		WPASupplicant.close();
	}
	else
	{
		cout << "Unable to open the Wi-Fi config file. Please run 'sudo wificonfig' and try again." << endl; 
	}

	//Disable Pi 3 internal Wi-Fi in config.txt
	ofstream bootconf("/boot/config.txt");
	if (bootconf.is_open())
	{					
		bootconf << "config_hdmi_boost=4" << endl;
		bootconf << "hdmi_force_hotplug=1" << endl;
		bootconf << "hdmi_drive=2" << endl;
		bootconf << "dtoverlay=pi3-disable-wifi";
		bootconf.close();
		cout << "Wi-Fi has been disabled. Please reboot the Pi for the changes to take effect." << endl;
	}
	else
	{
		cout << "Unable to open the boot config file. Please run 'sudo wificonfig' and try again." << endl; 
	}
}

void EraseNetworks()
{	
	ofstream WPASupplicant("/etc/wpa_supplicant/wpa_supplicant.conf", ofstream::out | ofstream::trunc);
	if (WPASupplicant.is_open())
	{			
		WPASupplicant.close();
		cout << "All Wi-Fi networks have been erased." << endl;
	}
	else
	{
		cout << "Unable to open the network config file. Please run 'sudo wificonfig' and try again." << endl; 
	}	
}

void DisplayIP()
{

system("hostname -I");

}

int main(int argc, char *argv[])
{
	int Selection;
	string UserInput;
	string WifiPass;
	string SSID;
	string CountryCode;

	cout << endl;
	cout << "Welcome to the Wi-Fi configuration wizard!" << endl;

	cout << endl;
	cout << "Your IP address is:" << endl;
	DisplayIP();
	cout << endl;

	cout << "Please select an option:" << endl;
	cout << "[1] Enable Wi-Fi" << endl;
	cout << "[2] Disable Wi-Fi" << endl;
	cout << "[3] Add Wi-Fi Network" << endl;
	cout << "[4] Set Country Code" << endl;
	cout << "[5] Remove Wi-Fi Networks" << endl;
	cout << "[6] Exit" << endl;
	
selectcc3:		
		cin >> Selection;
		//Check to make sure cin is valid (i.e. an integer)
		if (!cin) {
     		cout << "Invalid selection. Please type a number between 1 and 6." << endl;
			cin.clear();
    		cin.ignore();
			goto selectcc3;
		}
		
	switch (Selection)
	{

	//User selected "Enable Wi-Fi"
	case 1:
		
		EnableWifi();
		break;
		
	//User selected "Disable Wi-Fi"	
	case 2:
		
		DisableWifi();
		break;
		
	//User selected "Add Wi-Fi Network"	
	case 3:
		
		cout << "Please select a network type:" << endl;
		cout << "[1] Secured (has password)" << endl;
		cout << "[2] Open (no password)" << endl;

selectcc2:		
		cin >> Selection;
		//Check to make sure cin is valid (i.e. an integer)
		if (!cin) {
     		cout << "Invalid selection. Please type either 1 or 2." << endl;
			cin.clear();
    		cin.ignore();
			goto selectcc2;
		}
		
		switch (Selection)
		{
			
		case 1:
			
enterssid:
			cin.ignore();
			cout << "Enter Network Name (SSID): " << endl;
			getline (cin,SSID);		
			cout << "Enter Password: " << endl;
			getline (cin, WifiPass);

confirm:	
			cout << "Is the above information correct? Y/N ";
			cin >> UserInput;
		
			if (UserInput == "Y" || UserInput == "y")
			{			
				AddWifiNetwork(SSID, WifiPass, CountryCode);
				EnableWifi();
			}
			else if (UserInput == "N" || UserInput == "n")
			{
				cout << endl;
				goto enterssid;
			}		
			else
			{
				cout << endl;
				goto confirm;
			}
			break;
			
		case 2:
			
enterssid2:
			cin.ignore();
			cout << "Enter Network Name (SSID): " << endl;
			getline (cin,SSID);		

confirm2:	
			cout << "Is the above information correct? Y/N ";
			cin >> UserInput;
		
			if (UserInput == "Y" || UserInput == "y")
			{			
				AddOpenWifiNetwork(SSID);
				EnableWifi();
			}
			else if (UserInput == "N" || UserInput == "n")
			{
				cout << endl;
				goto enterssid2;
			}		
			else
			{
				cout << endl;
				goto confirm2;
			}
			break;

		default:

			cout << "Invalid selection. Please type either 1 or 2." << endl;
			cin.clear();
    		cin.ignore();
			goto selectcc2;

		}		
		break;
		
	//User selected "Set Country Code"
	case 4:

		cout << "Please select your Country Code:" << endl;
		cout << "[1] United States" << endl;
		cout << "[2] United Kingdom" << endl;
		cout << "[3] France" << endl;
		cout << "[4] Germany" << endl;
		cout << "[5] Other (Enter Manually)" << endl;
selectcc:		
		cin >> Selection;
		//Check to make sure cin is valid (i.e. an integer)
		if (!cin) {
     		cout << "Invalid selection. Please type a number between 1 and 5." << endl;
			cin.clear();
    		cin.ignore();
			goto selectcc;
		}
		
		switch (Selection)

		{

		case 1:

			CountryCode="us";
			AddCountryCode(CountryCode);
			break;

		case 2:

			CountryCode="gb";
			AddCountryCode(CountryCode);
			break;

		case 3:

			CountryCode="fr";
			AddCountryCode(CountryCode);
			break;

		case 4:

			CountryCode="de";
			AddCountryCode(CountryCode);
			break;

		case 5:

			cout << "Enter Country Code: ";
			cin >> CountryCode;
			AddCountryCode(CountryCode);
			cout << endl;
			break;

		default:

			cout << "Invalid selection. Please type a number between 1 and 5." << endl;
			cin.clear();
    		cin.ignore();
			goto selectcc;
		}

	break;

	//User selected "Remove Wi-Fi networks"
	case 5:
	
confirmation:
		cout << "Are you sure? This will erase all Wi-Fi networks. Y/N";
		cin >> UserInput;
		
		if (UserInput == "Y" || UserInput == "y")
		{			
			EraseNetworks();
		}
		else if (UserInput == "N" || UserInput == "n")
		{
			cout << "Operation aborted. Exited wizard." << endl;
			break;
		}		
		else
		{
			cout << endl;
			goto confirmation;
		}
		
	//User selected "Exit"
	case 6:

		cout << "Exited wizard." << endl;
		break;

	default:

			cout << "Invalid selection. Please type a number between 1 and 6." << endl;
			cin.clear();
    		cin.ignore();
			goto selectcc3;

	}

	return 0;
	
}

