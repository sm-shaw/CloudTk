# CloudTk
CloudTk for HammerDB is a fork of [CloudTk](https://cloudtk.tcl-lang.org/) by Jeff Smith to deploy the HammerDB for Linux GUI within a web browser.

Before installing CloudTk, install the following additional packages in your Linux OS:
```
apt-get install tigervnc-standalone-server matchbox-window-manager libxss1
```

To deploy CloudTk for HammerDB install [HammerDB for Linux](https://www.hammerdb.com/docs/ch01s08.html) and download and extract [CloudTk](https://github.com/sm-shaw/CloudTk/releases/tag/1.4.0-51) into the top level HammerDB directory. You will then have a directory called CloudTk-1.4.0-51 in your HammerDB for Linux installation. 


If you wish to have SSL support in the certs directory under CloudTk-1.4.0-51 create a self-signed certificate as follows:
```
openssl req -new -x509 -days 365 -nodes -out server.pem -keyout skey.pem
```
Then cd to the CloudTk-1.4.0-51 directory and run the following command. You can change the ports to preferred values. 
```
./tclkit-Linux64 CloudTK.kit -library custom -port 8081 -https_port 8082
can't find package limit
Running with default file descriptor limit
/debug user "debug" password "-vve73mn6c-x"
httpd started on port 8081
secure httpd started on SSL port 8082
```
If you do not create an SSL certificate then you will see a message such as follows for SSL.  
```
SSL startup failed: Certificate "/home/hammerdb/HammerDB-4.9/cloudtk/certs/server.pem" not found
```
This does not impact the functionality over non-encrypted HTTP. The can't find package limit message can be safely ignored. 

Using your preferred web browser, navigate to the http or https port on the Linux host where HammerDB has been installed. 

<img width="930" alt="cloudtk1" src="https://github.com/sm-shaw/CloudTk/assets/38044085/20b1d54a-023e-4f71-ae6d-ef7637365849">

The CloudTk home page is displayed. Launch the HammerDB application with the Submit button.

<img width="930" alt="cloudtk2" src="https://github.com/sm-shaw/CloudTk/assets/38044085/9ce95296-7500-43b9-9b1f-b5060a9adb4c">

The HammerDB for Linux GUI application is displayed in the browser.

<img width="930" alt="cloudtk3" src="https://github.com/sm-shaw/CloudTk/assets/38044085/594bd8d1-92fe-4582-a627-f5eefe2d86e0">

You can now use HammerDB for Linux in the same way ([as detailed in the documentation](https://www.hammerdb.com/document.html)) as when displaying over a standard X windows display. 

HammerDB provides a Docker image on [dockerhub](https://hub.docker.com/r/tpcorg/hammerdb) to automatically deploy HammerDB-CloudTk with pre-installed database libraries.
