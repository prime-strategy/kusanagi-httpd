<LocationMatch "/(login|index.php/login|index.php/dashboard*|index.php/install*)">
	Order deny,allow
	Deny from all
	Allow from all
	Allow from 127.0.0.1
	AuthType Basic
	AuthName "ENTER YOUR NAME & PASSWORD TO LOGIN"
	AuthUserFile /home/kusanagi/.htpasswd
	Require valid-user
	Satisfy any
</LocationMatch>
