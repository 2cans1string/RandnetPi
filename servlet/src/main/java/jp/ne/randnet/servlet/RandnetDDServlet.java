package jp.ne.randnet.servlet;

import javax.servlet.Filter;
import javax.servlet.FilterChain;
import javax.servlet.FilterConfig;
import javax.servlet.ServletException;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.InputStream;
import java.util.logging.Logger;

public class RandnetDDServlet implements Filter {

    private static final Logger log = Logger.getLogger(RandnetDDServlet.class.getName());

    @Override
    public void init(FilterConfig config) throws ServletException {}

    @Override
    public void destroy() {}

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest req   = (HttpServletRequest) request;
        HttpServletResponse resp = (HttpServletResponse) response;

        String host = req.getHeader("Host");
        if (!isRandnetDDHost(host)) {
            chain.doFilter(request, response);
            return;
        }

        String path = req.getRequestURI();
        String ctx  = req.getContextPath();
        if (!ctx.isEmpty() && path.startsWith(ctx)) {
            path = path.substring(ctx.length());
        }

        if (path.contains("..")) {
            resp.sendError(HttpServletResponse.SC_FORBIDDEN);
            return;
        }

        path = "/randnetdd" + path;

        if (path.endsWith("/")) {
            path = path + "index.html";
        } else if (!hasExtension(path)) {
            path = path + "/index.html";
        }

        InputStream is = req.getServletContext().getResourceAsStream(path);
        if (is == null) {
            log.warning("RandnetDD not found: " + path);
            resp.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }

        log.info("RandnetDD: " + req.getRequestURI() + " -> " + path);
        byte[] content = is.readAllBytes();
        is.close();

        String name = path.toLowerCase();
        if (name.endsWith(".html") || name.endsWith(".htm")) {
            resp.setContentType("text/html");
            resp.setCharacterEncoding("Shift_JIS");
        } else if (name.endsWith(".css")) {
            resp.setContentType("text/css");
        } else if (name.endsWith(".js")) {
            resp.setContentType("application/javascript");
        } else if (name.endsWith(".gif")) {
            resp.setContentType("image/gif");
        } else if (name.endsWith(".jpg") || name.endsWith(".jpeg")) {
            resp.setContentType("image/jpeg");
        } else if (name.endsWith(".png")) {
            resp.setContentType("image/png");
        } else {
            resp.setContentType("application/octet-stream");
        }
        resp.setContentLength(content.length);
        resp.getOutputStream().write(content);
    }

    private static boolean isRandnetDDHost(String host) {
        if (host == null) return false;
        int colon = host.indexOf(':');
        String hostname = (colon >= 0) ? host.substring(0, colon) : host;
        return "www.randnetdd.co.jp".equals(hostname) || "randnetdd.co.jp".equals(hostname);
    }

    private static boolean hasExtension(String path) {
        int lastSlash = path.lastIndexOf('/');
        int lastDot   = path.lastIndexOf('.');
        return lastDot > lastSlash;
    }
}
