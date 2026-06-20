package jp.ne.randnet.servlet;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.logging.Logger;

public class StaticContentServlet extends HttpServlet {

    private static final Logger log = Logger.getLogger(StaticContentServlet.class.getName());

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {
        serve(req, resp);
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse resp)
            throws ServletException, IOException {
        serve(req, resp);
    }

    private void serve(HttpServletRequest req, HttpServletResponse resp) throws IOException {
        String servletPath = req.getServletPath();
        String pathInfo    = req.getPathInfo();
        String fullPath    = (pathInfo != null) ? servletPath + pathInfo : servletPath;

        if (fullPath.contains("..")) {
            resp.sendError(HttpServletResponse.SC_FORBIDDEN);
            return;
        }

        String realPath = getServletContext().getRealPath(fullPath);
        if (realPath == null) {
            resp.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }

        File file = new File(realPath);

        // Directory: try index.html then index.htm
        if (file.isDirectory()) {
            File idx = new File(realPath, "index.html");
            if (!idx.exists()) idx = new File(realPath, "index.htm");
            if (idx.exists()) file = idx;
        }

        if (!file.exists() || !file.isFile()) {
            log.warning("Static not found: " + fullPath);
            resp.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }

        log.info("Static: " + fullPath + " -> " + file.getName());
        byte[] content = Files.readAllBytes(file.toPath());
        resp.setContentType("text/html");
        resp.setCharacterEncoding("Shift_JIS");
        resp.setContentLength(content.length);
        resp.getOutputStream().write(content);
    }
}
